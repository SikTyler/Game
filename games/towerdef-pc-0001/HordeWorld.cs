using System;
using System.Runtime.CompilerServices;
using Godot;

// MASS_HORDE §Architecture: the C#-resident horde world.
//
// Every body's kinematic + status state lives here, in double SoA arrays that
// stay on the C# side for the whole run (no per-call array marshalling in).
// GDScript (EnemyStore.gd) owns slot allocation and the rules data (hp, cash,
// shields, kinds) and pushes a body once at spawn (Put) plus small status
// writes (SetSlow / SetHit / Impulse ...). Per sim step it pulls ONE packed
// mirror (Pull) for the rules/view to read.
//
// Step = flow-field seek + mass-weighted pressure/separation (uniform hash)
// + knockback velocity with friction + projection out of the Core ring and
// building squares + contact attacks (building hits aggregated per building).
// Deterministic: doubles, ascending slot order, Jacobi reads of the step-start
// positions, no RNG, no threads, no trig in the step.
[GlobalClass]
public partial class HordeWorld : RefCounted
{
	public const int ACT_BLD = 0, ACT_SHOT = 1, ACT_HIT = 2, ACT_ESCAPE = 3, ACT_BOOM = 4;
	public const int KC_OTHER = 0, KC_COURIER = 1, KC_RANGED = 2, KC_BOSS = 3, KC_SAPPER = 4;
	const int F_EXIT = 2;

	// ---------------------------------------------------------------- bodies
	int cap = 0;
	double[] px = new double[0], py = new double[0], vx = new double[0], vy = new double[0];
	double[] rad = new double[0], spd = new double[0], dmg = new double[0], curS = new double[0];
	double[] slowT = new double[0], slowM = new double[0], shockT = new double[0], hitT = new double[0];
	double[] tauntT = new double[0], atkCd = new double[0], fireCd = new double[0];
	double[] exX = new double[0], exY = new double[0];
	int[] kc = new int[0], flg = new int[0];
	byte[] live = new byte[0];   // 1 = stored and alive (hp > 0), 0 = free or dead
	// step scratch
	double[] ox = new double[0], oy = new double[0], pushX = new double[0], pushY = new double[0];
	double[] front = new double[0], dirX = new double[0], dirY = new double[0], want = new double[0];
	byte[] mode = new byte[0];   // 0 skip, 1 flow seek, 2 direct seek, 3 hold at the stop ring, 4 pinned (taunt)

	// ---------------------------------------------------------------- arena
	double cx = 360.0, cy = 470.0, stopR = 34.0, bcell = 52.0;
	int side = 11;

	// ---------------------------------------------------------------- tunables (SetParams)
	double accelK = 6.0, sepK = 0.5, sepCap = 0.35, friction = 6.0;
	int kmax = 24;
	double frontK = 10.0, bldCost = 40.0, knockMax = 600.0, bldInset = 1.0, attackDot = 0.25;

	// ---------------------------------------------------------------- flow field
	const int FLOW_PER_CELL = 4;   // flow cells per building cell (52 / 4 = 13 px)
	const int FLOW_MARGIN = 13;    // building cells of open ground beyond the 11x11 grid (covers the spawn ring; outside it bodies seek the Core directly)
	double fc = 13.0, fox = 0.0, foy = 0.0;
	int fw = 0;
	double[] fdist = new double[0], fvx = new double[0], fvy = new double[0];
	byte[] fblk = new byte[0];
	byte[] bldBlk = new byte[0];     // last building occupancy (per building slot)
	int[] bldList = new int[0];      // standing building slots
	int bldCount = 0;
	public int FlowRebuilds = 0;
	long flowUs = 0;

	// ---------------------------------------------------------------- spatial hash
	const double HCELL = 16.0;
	const double HHALF = 1032.0;
	int hgw = 0;
	double hox = 0.0, hoy = 0.0;
	int[] cstart = new int[0], cfill = new int[0], sIdx = new int[0], cellOf = new int[0];
	double[] sX = new double[0], sY = new double[0], sR = new double[0], sVX = new double[0], sVY = new double[0];
	double[] lvx = new double[0], lvy = new double[0];   // last step's realised velocity (front-blocking yields to a body moving away)
	bool qdirty = true;               // query hash stale (positions / membership changed)
	int[] qhead = new int[0], qlink = new int[0];

	// ---------------------------------------------------------------- outputs
	double[] bldHits = new double[0], bldDmg = new double[0];
	long stepUs = 0;
	long[] passUs = new long[4];
	int lastAlive = 0, maxCell = 0;
	readonly System.Diagnostics.Stopwatch sw = new System.Diagnostics.Stopwatch();

	public HordeWorld()
	{
		Configure(cx, cy, stopR, side, bcell);
	}

	// Arena geometry (TowerState constants). Resets the flow field.
	public void Configure(double centerX, double centerY, double coreStopR, int gridSide, double cellPx)
	{
		cx = centerX; cy = centerY; stopR = coreStopR; side = gridSide; bcell = cellPx;
		fc = bcell / FLOW_PER_CELL;
		fw = (side + 2 * FLOW_MARGIN) * FLOW_PER_CELL;
		fox = cx - bcell * (side * 0.5 + FLOW_MARGIN);
		foy = cy - bcell * (side * 0.5 + FLOW_MARGIN);
		fdist = new double[fw * fw]; fvx = new double[fw * fw]; fvy = new double[fw * fw]; fblk = new byte[fw * fw];
		bldBlk = new byte[side * side];
		bldList = new int[side * side];
		bldCount = 0;
		bldHits = new double[side * side]; bldDmg = new double[side * side];
		hgw = (int)Math.Ceiling(2.0 * HHALF / HCELL);
		hox = cx - HHALF; hoy = cy - HHALF;
		qhead = new int[hgw * hgw];
		RebuildFlow();
		qdirty = true;
	}

	// prm = [accel_k, sep_k, sep_cap, friction, kmax, front_k, bld_cost, knock_max]
	public void SetParams(double[] prm)
	{
		if (prm.Length > 0) accelK = prm[0];
		if (prm.Length > 1) sepK = prm[1];
		if (prm.Length > 2) sepCap = prm[2];
		if (prm.Length > 3) friction = prm[3];
		if (prm.Length > 4) kmax = Math.Max(1, (int)prm[4]);
		if (prm.Length > 5) frontK = prm[5];
		if (prm.Length > 6 && prm[6] != bldCost) { bldCost = prm[6]; RebuildFlow(); }
		if (prm.Length > 7) knockMax = prm[7];
	}

	// ================================================================ storage
	public int Capacity() { return cap; }

	public void Ensure(int c)
	{
		if (c <= cap) return;
		Array.Resize(ref px, c); Array.Resize(ref py, c); Array.Resize(ref vx, c); Array.Resize(ref vy, c);
		Array.Resize(ref rad, c); Array.Resize(ref spd, c); Array.Resize(ref dmg, c); Array.Resize(ref curS, c);
		Array.Resize(ref slowT, c); Array.Resize(ref slowM, c); Array.Resize(ref shockT, c); Array.Resize(ref hitT, c);
		Array.Resize(ref tauntT, c); Array.Resize(ref atkCd, c); Array.Resize(ref fireCd, c);
		Array.Resize(ref exX, c); Array.Resize(ref exY, c); Array.Resize(ref lvx, c); Array.Resize(ref lvy, c);
		Array.Resize(ref kc, c); Array.Resize(ref flg, c); Array.Resize(ref live, c);
		ox = new double[c]; oy = new double[c]; pushX = new double[c]; pushY = new double[c];
		front = new double[c]; dirX = new double[c]; dirY = new double[c]; want = new double[c];
		mode = new byte[c]; qlink = new int[c];
		cap = c;
	}

	public void Clear()
	{
		Array.Clear(live, 0, cap);
		qdirty = true;
	}

	// f = [x, y, size, spd, dmg, exit_x, exit_y, atk_cd, fire_cd, slow_t, slow_m,
	//      shock_t, hit_t, taunt_t, cur_s, vx, vy, hp]
	public void Put(int s, int kcode, int flags, double[] f)
	{
		if (s >= cap) Ensure(Math.Max(64, NextPow2(s + 1)));
		px[s] = f[0]; py[s] = f[1]; rad[s] = f[2] * 0.5; spd[s] = f[3]; dmg[s] = f[4];
		exX[s] = f[5]; exY[s] = f[6]; atkCd[s] = f[7]; fireCd[s] = f[8]; slowT[s] = f[9]; slowM[s] = f[10];
		shockT[s] = f[11]; hitT[s] = f[12]; tauntT[s] = f[13]; curS[s] = f[14]; vx[s] = f[15]; vy[s] = f[16];
		kc[s] = kcode; flg[s] = flags; lvx[s] = 0.0; lvy[s] = 0.0;
		live[s] = (byte)(f[17] > 0.0 ? 1 : 0);
		qdirty = true;
	}

	static int NextPow2(int v) { int p = 1; while (p < v) p <<= 1; return p; }

	public void Remove(int s) { if (s < cap) { live[s] = 0; qdirty = true; } }
	public void MarkDead(int s) { if (s < cap && live[s] != 0) { live[s] = 0; qdirty = true; } }
	public bool IsLive(int s) { return s >= 0 && s < cap && live[s] != 0; }
	public void SetSlow(int s, double t, double m) { slowT[s] = t; slowM[s] = m; }
	public void SetHit(int s, double t) { hitT[s] = t; }
	public void SetShock(int s, double t) { shockT[s] = t; }
	public void SetTaunt(int s, double t) { tauntT[s] = t; }
	public void SetVel(int s, double x, double y) { vx[s] = x; vy[s] = y; }
	public void SetSpd(int s, double v) { spd[s] = v; }
	public void SetPos(int s, double x, double y) { px[s] = x; py[s] = y; qdirty = true; }

	public int Alive()
	{
		int n = 0;
		for (int s = 0; s < cap; s++) if (live[s] != 0) n++;
		return n;
	}

	// One packed mirror (first n slots) for the rules / view:
	// [pos, vel, cur_s, slow_t, slow_m, shock_t, hit_t, taunt_t, atk_cd, fire_cd]
	public Godot.Collections.Array Pull(int n)
	{
		n = Math.Min(n, cap);
		var pos = new Vector2[n];
		var vel = new Vector2[n];
		for (int s = 0; s < n; s++)
		{
			pos[s] = new Vector2((float)px[s], (float)py[s]);
			vel[s] = new Vector2((float)vx[s], (float)vy[s]);
		}
		return new Godot.Collections.Array {
			pos, vel, Head(curS, n), Head(slowT, n), Head(slowM, n), Head(shockT, n),
			Head(hitT, n), Head(tauntT, n), Head(atkCd, n), Head(fireCd, n) };
	}

	static double[] Head(double[] a, int n) { var o = new double[n]; Array.Copy(a, o, n); return o; }

	// Positions only (the per-step mirror the rules read most).
	public Vector2[] Positions()
	{
		var pos = new Vector2[cap];
		for (int s = 0; s < cap; s++) pos[s] = new Vector2((float)px[s], (float)py[s]);
		return pos;
	}

	// Spawn-order reap helper: splits `order` into [alive, dead] by the live flag.
	public Godot.Collections.Array SplitOrder(int[] order)
	{
		int na = 0;
		for (int k = 0; k < order.Length; k++) if (live[order[k]] != 0) na++;
		var a = new int[na];
		var d = new int[order.Length - na];
		int ia = 0, id = 0;
		for (int k = 0; k < order.Length; k++)
		{
			int s = order[k];
			if (live[s] != 0) a[ia++] = s; else d[id++] = s;
		}
		return new Godot.Collections.Array { a, d };
	}

	// ================================================================ flow field
	// Building occupancy (1 byte per building slot). Rebuilds the flow field
	// only when the set changed (place / sell / destroy / move).
	public bool SetBuildings(byte[] blk)
	{
		int n = side * side;
		bool same = true;
		for (int i = 0; i < n; i++)
		{
			byte b = (blk != null && i < blk.Length) ? blk[i] : (byte)0;
			if (bldBlk[i] != b) { same = false; bldBlk[i] = b; }
		}
		if (same) return false;
		RebuildFlow();
		return true;
	}

	struct Heap
	{
		public double[] k; public int[] v; public int n;
		public void Init(int c) { k = new double[c]; v = new int[c]; n = 0; }
		bool Less(int a, int b) { return k[a] < k[b] || (k[a] == k[b] && v[a] < v[b]); }
		void Swap(int a, int b) { (k[a], k[b]) = (k[b], k[a]); (v[a], v[b]) = (v[b], v[a]); }
		public void Push(double key, int val)
		{
			if (n == k.Length) { Array.Resize(ref k, n * 2); Array.Resize(ref v, n * 2); }
			k[n] = key; v[n] = val; int i = n++;
			while (i > 0) { int p = (i - 1) >> 1; if (!Less(i, p)) break; Swap(i, p); i = p; }
		}
		public void Pop(out double key, out int val)
		{
			key = k[0]; val = v[0]; n--;
			if (n > 0)
			{
				k[0] = k[n]; v[0] = v[n]; int i = 0;
				while (true)
				{
					int l = 2 * i + 1, r = l + 1, m = i;
					if (l < n && Less(l, m)) m = l;
					if (r < n && Less(r, m)) m = r;
					if (m == i) break;
					Swap(i, m); i = m;
				}
			}
		}
	}

	// 16-neighbourhood (orthogonal, diagonal, knight moves): a much closer
	// approximation of Euclidean distance than 8-neighbour octile cost, so the
	// flow aims at a wall's corner from afar instead of "down, then sideways".
	static readonly int[] NX = { 1, -1, 0, 0, 1, 1, -1, -1, 2, 2, -2, -2, 1, 1, -1, -1 };
	static readonly int[] NY = { 0, 0, 1, -1, 1, -1, 1, -1, 1, -1, 1, -1, 2, -2, 2, -2 };
	static readonly double[] NL = { 1, 1, 1, 1, 1.4142135623730951, 1.4142135623730951, 1.4142135623730951, 1.4142135623730951,
		2.23606797749979, 2.23606797749979, 2.23606797749979, 2.23606797749979, 2.23606797749979, 2.23606797749979, 2.23606797749979, 2.23606797749979 };
	const int NDIR = 16;

	// The cells a move sweeps past (must be open when leaving an open cell): no corner cutting.
	bool MoveClear(int gx, int gy, int d)
	{
		if (d < 4) return true;
		int dx = NX[d], dy = NY[d];
		int sx = Math.Sign(dx), sy = Math.Sign(dy);
		int ax, ay, bx, by;
		if (d < 8) { ax = sx; ay = 0; bx = 0; by = sy; }
		else if (Math.Abs(dx) == 2) { ax = sx; ay = 0; bx = sx; by = sy; }
		else { ax = 0; ay = sy; bx = sx; by = sy; }
		return fblk[(gy + ay) * fw + gx + ax] == 0 && fblk[(gy + by) * fw + gx + bx] == 0;
	}

	[MethodImpl(MethodImplOptions.AggressiveOptimization)]
	void RebuildFlow()
	{
		sw.Restart();
		FlowRebuilds++;
		int n = fw * fw;
		Array.Clear(fblk, 0, n);
		bldCount = 0;
		int half = side / 2;
		for (int i = 0; i < side * side; i++)
		{
			if (bldBlk[i] == 0 || i == half * side + half) continue;
			bldList[bldCount++] = i;
			int col = i % side, row = i / side;
			int gx0 = (FLOW_MARGIN + col) * FLOW_PER_CELL, gy0 = (FLOW_MARGIN + row) * FLOW_PER_CELL;
			for (int yy = 0; yy < FLOW_PER_CELL; yy++)
				for (int xx = 0; xx < FLOW_PER_CELL; xx++)
					fblk[(gy0 + yy) * fw + gx0 + xx] = 1;
		}
		for (int i = 0; i < n; i++) fdist[i] = double.PositiveInfinity;
		var h = new Heap(); h.Init(1024);
		double seedR = stopR + fc;
		for (int gy = 0; gy < fw; gy++)
			for (int gx = 0; gx < fw; gx++)
			{
				double ccx = fox + (gx + 0.5) * fc - cx, ccy = foy + (gy + 0.5) * fc - cy;
				double d = Math.Sqrt(ccx * ccx + ccy * ccy);
				if (d <= seedR)
				{
					int i = gy * fw + gx;
					fdist[i] = d / fc;
					h.Push(fdist[i], i);
				}
			}
		const double D = 1.4142135623730951;
		while (h.n > 0)
		{
			h.Pop(out double k, out int i);
			if (k > fdist[i]) continue;
			int gx = i % fw, gy = i / fw;
			for (int d = 0; d < NDIR; d++)
			{
				int nx = gx + NX[d], ny = gy + NY[d];
				if (nx < 0 || ny < 0 || nx >= fw || ny >= fw) continue;
				int j = ny * fw + nx;
				// Dijkstra runs outward from the Core; a walker moves j -> i, so it
				// pays to ENTER i, and the sweep must be clear when it leaves an open j
				// (the swept cells of a move are the same from either end).
				if (fblk[j] == 0 && !MoveClear(gx, gy, d)) continue;
				double c = NL[d] * (fblk[i] != 0 ? bldCost : 1.0);
				double nk = k + c;
				if (nk < fdist[j]) { fdist[j] = nk; h.Push(nk, j); }
			}
		}
		// Unit flow vector per cell: the negative gradient of the cost field
		// (central differences over open neighbours; a building neighbour of an
		// open cell counts as the cell itself, so walls never repel the flow).
		// Falls back to the cheapest neighbour when the gradient vanishes.
		for (int gy = 0; gy < fw; gy++)
			for (int gx = 0; gx < fw; gx++)
			{
				int i = gy * fw + gx;
				double ccx = cx - (fox + (gx + 0.5) * fc), ccy = cy - (foy + (gy + 0.5) * fc);
				double l = Math.Sqrt(ccx * ccx + ccy * ccy);
				if (l <= stopR + fc)
				{
					if (l > 0.0) { fvx[i] = ccx / l; fvy[i] = ccy / l; } else { fvx[i] = 0.0; fvy[i] = 0.0; }
					continue;
				}
				double c0 = fdist[i];
				double xl = Nb(gx - 1, gy, i, c0), xr = Nb(gx + 1, gy, i, c0);
				double yu = Nb(gx, gy - 1, i, c0), yd = Nb(gx, gy + 1, i, c0);
				double gxv = xl - xr, gyv = yu - yd;
				double gl = Math.Sqrt(gxv * gxv + gyv * gyv);
				if (gl > 1e-6) { fvx[i] = gxv / gl; fvy[i] = gyv / gl; continue; }
				double best = c0;
				int bd = -1;
				for (int d = 0; d < NDIR; d++)
				{
					int nx = gx + NX[d], ny = gy + NY[d];
					if (nx < 0 || ny < 0 || nx >= fw || ny >= fw) continue;
					double v = fdist[ny * fw + nx];
					if (v < best) { best = v; bd = d; }
				}
				if (bd < 0) { fvx[i] = ccx / l; fvy[i] = ccy / l; }
				else { fvx[i] = NX[bd] / NL[bd]; fvy[i] = NY[bd] / NL[bd]; }
			}
		sw.Stop();
		flowUs = sw.Elapsed.Ticks / 10;
		qdirty = true;
	}

	// Cost of neighbour (x, y) for the gradient: off-grid, or a building next
	// to an open cell, reads as the centre cell's own cost (one-sided difference).
	double Nb(int x, int y, int i, double c0)
	{
		if (x < 0 || y < 0 || x >= fw || y >= fw) return c0;
		int j = y * fw + x;
		if (fblk[j] != 0 && fblk[i] == 0) return c0;
		return fdist[j];
	}

	// Bilinear flow sample; false outside the flow grid (seek the Core directly).
	[MethodImpl(MethodImplOptions.AggressiveOptimization)]
	bool FlowAt(double x, double y, out double dx, out double dy)
	{
		double u = (x - fox) / fc - 0.5, v = (y - foy) / fc - 0.5;
		dx = 0.0; dy = 0.0;
		if (u < 0.0 || v < 0.0 || u >= fw - 1 || v >= fw - 1) return false;
		int x0 = (int)u, y0 = (int)v;
		double tx = u - x0, ty = v - y0;
		int i = y0 * fw + x0;
		double ax = fvx[i] * (1 - tx) + fvx[i + 1] * tx, ay = fvy[i] * (1 - tx) + fvy[i + 1] * tx;
		double bx = fvx[i + fw] * (1 - tx) + fvx[i + fw + 1] * tx, by = fvy[i + fw] * (1 - tx) + fvy[i + fw + 1] * tx;
		dx = ax * (1 - ty) + bx * ty; dy = ay * (1 - ty) + by * ty;
		double l = Math.Sqrt(dx * dx + dy * dy);
		if (l < 1e-9) return false;
		dx /= l; dy /= l;
		return true;
	}

	// Flow direction at a point (selftest / debug view).
	public Vector2 FlowDir(double x, double y)
	{
		if (!FlowAt(x, y, out double dx, out double dy))
		{
			dx = cx - x; dy = cy - y;
			double l = Math.Sqrt(dx * dx + dy * dy);
			if (l > 0) { dx /= l; dy /= l; }
		}
		return new Vector2((float)dx, (float)dy);
	}

	// True when the cheapest move out of the flow cell at (x, y) enters a building cell.
	bool RouteThroughBuilding(double x, double y)
	{
		int gx = (int)Math.Floor((x - fox) / fc), gy = (int)Math.Floor((y - foy) / fc);
		if (gx < 0 || gy < 0 || gx >= fw || gy >= fw) return false;
		int i = gy * fw + gx;
		double best = double.PositiveInfinity;
		int bj = -1;
		for (int d = 0; d < NDIR; d++)
		{
			int nx = gx + NX[d], ny = gy + NY[d];
			if (nx < 0 || ny < 0 || nx >= fw || ny >= fw) continue;
			if (fblk[i] == 0 && !MoveClear(gx, gy, d)) continue;
			int j = ny * fw + nx;
			double c = fdist[j] + NL[d] * (fblk[j] != 0 ? bldCost : 1.0);
			if (c < best) { best = c; bj = j; }
		}
		return bj >= 0 && fblk[bj] != 0;
	}

	double CostAt(double x, double y)
	{
		int gx = (int)Math.Floor((x - fox) / fc), gy = (int)Math.Floor((y - foy) / fc);
		if (gx < 0 || gy < 0 || gx >= fw || gy >= fw) return double.PositiveInfinity;
		return fdist[gy * fw + gx];
	}

	// Integrated path cost (flow cells) from a point to the Core; -1 outside the grid.
	public double FlowCost(double x, double y)
	{
		int gx = (int)Math.Floor((x - fox) / fc), gy = (int)Math.Floor((y - foy) / fc);
		if (gx < 0 || gy < 0 || gx >= fw || gy >= fw) return -1.0;
		return fdist[gy * fw + gx];
	}

	// ================================================================ buildings
	void BldRect(int i, out double x0, out double y0, out double x1, out double y1)
	{
		int half = side / 2;
		double bx = cx + (i % side - half) * bcell, by = cy + (i / side - half) * bcell;
		double h = bcell * 0.5 - bldInset;
		x0 = bx - h; x1 = bx + h; y0 = by - h; y1 = by + h;
	}

	// Push body s out of every standing building square near it. Returns the
	// building it is pressing into (flow toward it), or -1.
	double pressNx, pressNy;   // outward face normal of the building ResolveBuildings returned

	[MethodImpl(MethodImplOptions.AggressiveOptimization)]
	int ResolveBuildings(int s, double ddx, double ddy)
	{
		if (bldCount == 0) return -1;
		int half = side / 2;
		double r = rad[s];
		double gxf = (px[s] - cx) / bcell + half + 0.5, gyf = (py[s] - cy) / bcell + half + 0.5;
		int gx = (int)Math.Floor(gxf), gy = (int)Math.Floor(gyf);
		if (gx < -1 || gy < -1 || gx > side || gy > side) return -1;
		int press = -1;
		double bestDot = attackDot;
		for (int yy = gy - 1; yy <= gy + 1; yy++)
		{
			if (yy < 0 || yy >= side) continue;
			for (int xx = gx - 1; xx <= gx + 1; xx++)
			{
				if (xx < 0 || xx >= side) continue;
				int bi = yy * side + xx;
				if (bldBlk[bi] == 0 || bi == half * side + half) continue;
				BldRect(bi, out double x0, out double y0, out double x1, out double y1);
				double qx = Math.Clamp(px[s], x0, x1), qy = Math.Clamp(py[s], y0, y1);
				double dx = px[s] - qx, dy = py[s] - qy;
				double d2 = dx * dx + dy * dy;
				if (d2 >= (r + 0.5) * (r + 0.5)) continue;
				double nxv, nyv;
				if (d2 > 1e-12)
				{
					double l = Math.Sqrt(d2);
					nxv = dx / l; nyv = dy / l;
					if (l < r) { px[s] = qx + nxv * r; py[s] = qy + nyv * r; }
				}
				else
				{
					// centre inside the square: leave along the shallowest axis
					double el = px[s] - x0, er = x1 - px[s], et = py[s] - y0, eb = y1 - py[s];
					double m = Math.Min(Math.Min(el, er), Math.Min(et, eb));
					nxv = 0; nyv = 0;
					if (m == el) { nxv = -1; px[s] = x0 - r; }
					else if (m == er) { nxv = 1; px[s] = x1 + r; }
					else if (m == et) { nyv = -1; py[s] = y0 - r; }
					else { nyv = 1; py[s] = y1 + r; }
				}
				double vn = vx[s] * nxv + vy[s] * nyv;
				if (vn < 0) { vx[s] -= vn * nxv; vy[s] -= vn * nyv; }
				double dot = -(ddx * nxv + ddy * nyv);   // flow pressing into the face
				if (dot > bestDot) { bestDot = dot; press = bi; pressNx = nxv; pressNy = nyv; }
			}
		}
		return press;
	}

	// ================================================================ hash
	int HX(double x) { int i = (int)Math.Floor((x - hox) / HCELL); return i < 0 ? 0 : (i >= hgw ? hgw - 1 : i); }
	int HY(double y) { int i = (int)Math.Floor((y - hoy) / HCELL); return i < 0 ? 0 : (i >= hgw ? hgw - 1 : i); }

	// Bucket lists come out in ascending slot order (built descending, head insert).
	void BuildHash(int[] hd, int[] lk, double[] X, double[] Y, bool skipCourier)
	{
		Array.Fill(hd, -1);
		for (int s = cap - 1; s >= 0; s--)
		{
			if (live[s] == 0) continue;
			if (skipCourier && kc[s] == KC_COURIER) continue;
			int c = HY(Y[s]) * hgw + HX(X[s]);
			lk[s] = hd[c];
			hd[c] = s;
		}
	}

	void EnsureQuery()
	{
		if (!qdirty) return;
		BuildHash(qhead, qlink, px, py, false);
		qdirty = false;
	}

	// ================================================================ step
	// One fixed sim step. Returns the action log: [ACT_SHOT|ACT_HIT|ACT_ESCAPE, slot]
	// pairs in slot order, then [ACT_BLD, building_slot, hits] rows (building order)
	// whose damage sums are in LastBuildingDamage().
	[MethodImpl(MethodImplOptions.AggressiveOptimization)]
	public int[] Step(double dt, bool frozen, double rStop, double rFire, byte[] blk)
	{
		sw.Restart();
		stepDt = dt > 0.0 ? dt : 0.05;
		SetBuildings(blk);
		var acts = new System.Collections.Generic.List<int>(64);
		Array.Clear(bldHits, 0, bldHits.Length);
		Array.Clear(bldDmg, 0, bldDmg.Length);
		double fr = Math.Exp(-friction * dt);
		int alive = 0;
		// ---- pass 1: timers + desired motion
		for (int s = 0; s < cap; s++)
		{
			mode[s] = 0;
			if (live[s] == 0) continue;
			alive++;
			double st = slowT[s];
			double mult = st > 0.0 ? slowM[s] : 1.0;
			double st2 = Math.Max(0.0, st - dt);
			slowT[s] = st2;
			if (st2 <= 0.0) slowM[s] = 1.0;
			shockT[s] = Math.Max(0.0, shockT[s] - dt);
			hitT[s] = Math.Max(0.0, hitT[s] - dt);
			ox[s] = px[s]; oy[s] = py[s];
			pushX[s] = 0.0; pushY[s] = 0.0; front[s] = 0.0;
			if (frozen) continue;
			if (kc[s] == KC_COURIER)
			{
				double tx = (flg[s] & F_EXIT) != 0 ? exX[s] : px[s], ty = (flg[s] & F_EXIT) != 0 ? exY[s] : py[s];
				double ddx = tx - px[s], ddy = ty - py[s];
				double dl = Math.Sqrt(ddx * ddx + ddy * ddy);
				double stp = spd[s] * mult * dt;
				if (dl <= stp) { acts.Add(ACT_ESCAPE); acts.Add(s); }
				else { px[s] += ddx / dl * stp; py[s] += ddy / dl * stp; }
				curS[s] = spd[s] * mult;
				continue;
			}
			bool pinned = tauntT[s] > 0.0;
			if (pinned) tauntT[s] = Math.Max(0.0, tauntT[s] - dt);
			double stop = kc[s] == KC_RANGED ? rStop : stopR;
			double tcx = cx - px[s], tcy = cy - py[s];
			double dist = Math.Sqrt(tcx * tcx + tcy * tcy);
			double dx, dy;
			byte md;
			if (dist <= stop + fc * 2.0 || !FlowAt(px[s], py[s], out dx, out dy))
			{
				if (dist > 0) { dx = tcx / dist; dy = tcy / dist; } else { dx = 0; dy = 0; }
				md = 2;
			}
			else md = 1;
			dirX[s] = dx; dirY[s] = dy;
			if (pinned) { md = 4; curS[s] = 0.0; want[s] = 0.0; }
			else if (dist <= stop + 0.001) { md = 3; curS[s] = 0.0; want[s] = 0.0; }
			else
			{
				double vmax = spd[s] * mult;
				double cs = Math.Min(vmax, curS[s] + vmax * accelK * dt);
				curS[s] = cs;
				want[s] = md == 2 ? Math.Min(dist - stop, cs * dt) : cs * dt;
			}
			mode[s] = md;
		}
		lastAlive = alive;
		long tP1 = sw.Elapsed.Ticks;
		long tP2 = 0;
		if (!frozen)
		{
			// ---- cell-sorted copy of the step-start positions (couriers are a
			// top layer): counting sort, stable in slot order, so every bucket is
			// a contiguous, cache-friendly run and a 3-cell row is one range.
			int ncell = hgw * hgw;
			if (cstart.Length != ncell + 1) cstart = new int[ncell + 1];
			if (sIdx.Length < cap) { sIdx = new int[cap]; sX = new double[cap]; sY = new double[cap]; sR = new double[cap]; sVX = new double[cap]; sVY = new double[cap]; cellOf = new int[cap]; }
			Array.Clear(cstart, 0, ncell + 1);
			double bigR = HCELL * 0.5;
			double maxR = 0.0;
			int m = 0;
			for (int q = 0; q < cap; q++)
			{
				if (live[q] == 0 || kc[q] == KC_COURIER) { cellOf[q] = -1; continue; }
				int c = HY(oy[q]) * hgw + HX(ox[q]);
				cellOf[q] = c;
				cstart[c + 1]++;
				m++;
				if (rad[q] > maxR) maxR = rad[q];
			}
			for (int c = 0; c < ncell; c++) cstart[c + 1] += cstart[c];
			if (cfill.Length != ncell) cfill = new int[ncell];
			Array.Copy(cstart, cfill, ncell);
			for (int q = 0; q < cap; q++)
			{
				int c = cellOf[q];
				if (c < 0) continue;
				int k = cfill[c]++;
				sIdx[k] = q; sX[k] = ox[q]; sY[k] = oy[q]; sR[k] = rad[q]; sVX[k] = lvx[q]; sVY[k] = lvy[q];
			}
			// ---- pass 2: pairs involving a big body (radius > HCELL/2), applied to both sides
			for (int b = 0; b < cap; b++)
			{
				if (cellOf[b] < 0 || rad[b] <= bigR) continue;
				int reach = (int)Math.Ceiling((rad[b] + maxR) / HCELL);
				int bx = HX(ox[b]), by = HY(oy[b]);
				int xa = Math.Max(0, bx - reach), xb = Math.Min(hgw - 1, bx + reach);
				for (int yy = Math.Max(0, by - reach); yy <= Math.Min(hgw - 1, by + reach); yy++)
				{
					int t1 = cstart[yy * hgw + xb + 1];
					for (int t = cstart[yy * hgw + xa]; t < t1; t++)
					{
						int j = sIdx[t];
						if (j == b || (sR[t] > bigR && j < b)) continue;
						PairPush(b, j, true);
					}
				}
			}
			tP2 = sw.Elapsed.Ticks;
			// ---- pass 3: small-small pairs (3x3 cells, at most kmax overlapping
			// neighbours per body), in cell-sorted order; each body only writes
			// its own accumulators, so the visiting order cannot change results.
			for (int k = 0; k < m; k++)
			{
				int i = sIdx[k];
				double ri = sR[k];
				if (ri > bigR) continue;
				double xi = sX[k], yi = sY[k], mi = ri * ri;
				double dxi = dirX[i], dyi = dirY[i];
				double vdes = want[i] / dt;
				double ax = 0.0, ay = 0.0, fr0 = 0.0;
				int c = cellOf[i];
				int hx = c % hgw, hy = c / hgw;
				int xa = hx > 0 ? hx - 1 : 0, xb = hx < hgw - 1 ? hx + 1 : hgw - 1;
				int seen = 0;
				for (int yy = (hy > 0 ? hy - 1 : 0); yy <= (hy < hgw - 1 ? hy + 1 : hgw - 1) && seen < kmax; yy++)
				{
					int t1 = cstart[yy * hgw + xb + 1];
					for (int t = cstart[yy * hgw + xa]; t < t1; t++)
					{
						double rj = sR[t];
						if (rj > bigR) continue;
						double dx = xi - sX[t], dy = yi - sY[t];
						double rr = ri + rj;
						double d2 = dx * dx + dy * dy;
						if (d2 >= rr * rr) continue;
						int j = sIdx[t];
						if (j == i) continue;
						double l = Math.Sqrt(d2);
						double ux, uy;
						if (l > 1e-4) { ux = dx / l; uy = dy / l; }
						else { ux = i > j ? 1.0 : -1.0; uy = 0.0; l = 0.0; }
						double ov = rr - l;
						double mj = rj * rj;
						double w = mj / (mi + mj);
						ax += ux * ov * w; ay += uy * ov * w;
						double f = -(dxi * ux + dyi * uy);
						if (f > 0.0) fr0 += f * ov / rr * w * Yield(sVX[t] * dxi + sVY[t] * dyi, vdes);
						if (++seen >= kmax) break;
					}
				}
				pushX[i] += ax; pushY[i] += ay; front[i] += fr0;
			}
		}
		long tP3 = sw.Elapsed.Ticks;
		// ---- pass 4: integrate, constrain, contact
		for (int s = 0; s < cap; s++)
		{
			if (live[s] == 0 || frozen || kc[s] == KC_COURIER) continue;
			byte md = mode[s];
			if (md == 0) continue;
			double block = Math.Clamp(1.0 - frontK * front[s], 0.0, 1.0);
			double mx = dirX[s] * want[s] * block, my = dirY[s] * want[s] * block;
			if (block < 1.0) curS[s] *= block;
			double ppx = pushX[s] * sepK, ppy = pushY[s] * sepK;
			double cap2 = 2.0 * rad[s] * sepCap;
			double pl = Math.Sqrt(ppx * ppx + ppy * ppy);
			if (pl > cap2) { ppx *= cap2 / pl; ppy *= cap2 / pl; }
			mx += ppx; my += ppy;
			if (vx[s] != 0.0 || vy[s] != 0.0)
			{
				mx += vx[s] * dt; my += vy[s] * dt;
				vx[s] *= fr; vy[s] *= fr;
				if (vx[s] * vx[s] + vy[s] * vy[s] < 0.01) { vx[s] = 0.0; vy[s] = 0.0; }
			}
			px[s] = ox[s] + mx; py[s] = oy[s] + my;
			bool ranged = kc[s] == KC_RANGED;
			double stop = ranged ? rStop : stopR;
			double rx = px[s] - cx, ry = py[s] - cy;
			double nd = Math.Sqrt(rx * rx + ry * ry);
			if (nd < stop && nd > 0.0)
			{
				px[s] = cx + rx / nd * stop; py[s] = cy + ry / nd * stop; nd = stop;
				double vn = (vx[s] * rx + vy[s] * ry) / Math.Max(1e-9, Math.Sqrt(rx * rx + ry * ry));
				if (vn < 0) { vx[s] -= vn * rx / Math.Sqrt(rx * rx + ry * ry); vy[s] -= vn * ry / Math.Sqrt(rx * rx + ry * ry); }
			}
			int bi = ResolveBuildings(s, dirX[s], dirY[s]);
			if (bi >= 0 && md != 4 && kc[s] == KC_SAPPER)
			{
				// MASS_HORDE §D1 Sapper: detonates on the first structure it presses
				// (sealed or not); the rules apply the blast and reap the body.
				live[s] = 0; qdirty = true;
				acts.Add(ACT_BOOM); acts.Add(s); acts.Add(bi);
				continue;
			}
			if (bi >= 0 && md != 4)
			{
				// Pressing a face. Sealed path (the cheapest route from here runs
				// THROUGH a building: the best next cell is a building cell) ->
				// attack it. Otherwise the way round is cheaper: slide along the
				// face toward the cheaper side (a jet hitting a wall splits; exact
				// ties split by slot parity), so open-ground buildings are flowed around.
				double nxv = pressNx, nyv = pressNy;
				if (!RouteThroughBuilding(px[s] + nxv * fc * 0.25, py[s] + nyv * fc * 0.25))
				{
					double tx = -nyv, ty = nxv;
					double a = CostAt(px[s] + tx * fc * 2.0, py[s] + ty * fc * 2.0);
					double b2 = CostAt(px[s] - tx * fc * 2.0, py[s] - ty * fc * 2.0);
					double sg = a < b2 ? 1.0 : (b2 < a ? -1.0 : ((s & 1) == 0 ? 1.0 : -1.0));
					double slide = Math.Max(want[s], spd[s] * 0.5 * dt);
					px[s] += tx * sg * slide; py[s] += ty * sg * slide;
					ResolveBuildings(s, dirX[s], dirY[s]);
					bi = -1;
				}
			}
			lvx[s] = (px[s] - ox[s]) / stepDt; lvy[s] = (py[s] - oy[s]) / stepDt;
			rx = px[s] - cx; ry = py[s] - cy;
			nd = Math.Sqrt(rx * rx + ry * ry);
			if (md == 4) continue;   // pinned by a troop: it fights the troop, not the base
			if (bi >= 0 && !(md == 3 && nd <= stop + rad[s] + 0.5))
			{
				curS[s] = 0.0;
				atkCd[s] -= dt;
				if (atkCd[s] <= 0.0)
				{
					atkCd[s] = ranged ? rFire : 1.0;
					bldHits[bi] += 1.0;
					bldDmg[bi] += dmg[s];
				}
				continue;
			}
			if (nd > stop + rad[s] + 0.5) continue;
			if (ranged)
			{
				fireCd[s] -= dt;
				if (fireCd[s] <= 0.0) { fireCd[s] += rFire; acts.Add(ACT_SHOT); acts.Add(s); }
			}
			else
			{
				atkCd[s] -= dt;
				if (atkCd[s] <= 0.0) { atkCd[s] = 1.0; acts.Add(ACT_HIT); acts.Add(s); }
			}
		}
		for (int i = 0; i < bldHits.Length; i++)
			if (bldHits[i] > 0.0) { acts.Add(ACT_BLD); acts.Add(i); acts.Add((int)bldHits[i]); }
		qdirty = true;
		sw.Stop();
		stepUs = sw.Elapsed.Ticks / 10;
		passUs = new long[] { tP1 / 10, tP2 / 10, tP3 / 10, stepUs };
		return acts.ToArray();
	}

	// Mass-weighted overlap push between i and j (Jacobi: step-start positions).
	// `both` applies the mirrored push to j too (big-body pre-pass).
	// How much a body ahead blocks: 1 when it is not moving along my direction,
	// 0 when it moves away at least as fast as I want to go (a stream flows).
	static double Yield(double aheadSpeed, double myDesired)
	{
		if (aheadSpeed <= 0.0 || myDesired <= 1e-9) return 1.0;
		double y = 1.0 - aheadSpeed / myDesired;
		return y < 0.0 ? 0.0 : y;
	}

	double stepDt = 0.05;

	[MethodImpl(MethodImplOptions.AggressiveOptimization)]
	bool PairPush(int i, int j, bool both)
	{
		double dx = ox[i] - ox[j], dy = oy[i] - oy[j];
		double rr = rad[i] + rad[j];
		double d2 = dx * dx + dy * dy;
		if (d2 >= rr * rr) return false;
		double mi = rad[i] * rad[i], mj = rad[j] * rad[j];
		double l = Math.Sqrt(d2);
		double ux, uy;
		if (l > 1e-4) { ux = dx / l; uy = dy / l; }
		else { ux = i > j ? 1.0 : -1.0; uy = 0.0; l = 0.0; }
		double ov = rr - l;
		double wi = mj / (mi + mj);
		pushX[i] += ux * ov * wi; pushY[i] += uy * ov * wi;
		double fi = -(dirX[i] * ux + dirY[i] * uy);   // j ahead of i along i's motion
		if (fi > 0.0) front[i] += fi * ov / rr * wi * Yield(lvx[j] * dirX[i] + lvy[j] * dirY[i], want[i] / stepDt);
		if (both)
		{
			double wj = mi / (mi + mj);
			pushX[j] -= ux * ov * wj; pushY[j] -= uy * ov * wj;
			double fj = dirX[j] * ux + dirY[j] * uy;
			if (fj > 0.0) front[j] += fj * ov / rr * wj * Yield(lvx[i] * dirX[j] + lvy[i] * dirY[j], want[j] / stepDt);
		}
		return true;
	}

	public double[] LastBuildingDamage() { return (double[])bldDmg.Clone(); }

	// ================================================================ impulses
	// Knockback (GDScript knock() rule): v / max(0.25, (size/16)^2); bosses and
	// couriers immune. Clamped to knockMax.
	public void Impulse(int s, double ix, double iy)
	{
		if (s < 0 || s >= cap || live[s] == 0 || kc[s] == KC_BOSS || kc[s] == KC_COURIER) return;
		double m = rad[s] * 2.0 / 16.0;
		double k = 1.0 / Math.Max(0.25, m * m);
		vx[s] += ix * k; vy[s] += iy * k;
		double l = Math.Sqrt(vx[s] * vx[s] + vy[s] * vy[s]);
		if (l > knockMax) { vx[s] *= knockMax / l; vy[s] *= knockMax / l; }
	}

	// Radial impulse with falloff k*(1 - 0.5 d/r) (mortar / specials). Returns bodies pushed.
	public int RadialImpulse(double x, double y, double r, double k)
	{
		if (r <= 0.0 || k == 0.0) return 0;
		int n = 0;
		foreach (int s in Circle(x, y, r, false))
		{
			double dx = px[s] - x, dy = py[s] - y;
			double l = Math.Sqrt(dx * dx + dy * dy);
			if (l > 0.0 && l <= r)
			{
				double f = k * (1.0 - 0.5 * l / r);
				if (kc[s] != KC_BOSS && kc[s] != KC_COURIER) n++;
				Impulse(s, dx / l * f, dy / l * f);
			}
		}
		return n;
	}

	// Slow everything in a radius (frost / auras): t = max, m = min (the rules' merge).
	public int SlowRadius(double x, double y, double r, double t, double m)
	{
		int n = 0;
		foreach (int s in Circle(x, y, r, false))
		{
			slowM[s] = Math.Min(slowT[s] > 0.0 ? slowM[s] : 1.0, m);
			slowT[s] = Math.Max(slowT[s], t);
			n++;
		}
		return n;
	}

	// ================================================================ queries (living bodies, ascending slot)
	[MethodImpl(MethodImplOptions.AggressiveOptimization)]
	System.Collections.Generic.List<int> Circle(double x, double y, double r, bool pad)
	{
		EnsureQuery();
		var outl = new System.Collections.Generic.List<int>();
		double rr = r + (pad ? 32.0 : 0.0) + 1.0;
		int x0 = HX(x - rr), x1 = HX(x + rr), y0 = HY(y - rr), y1 = HY(y + rr);
		for (int yy = y0; yy <= y1; yy++)
			for (int xx = x0; xx <= x1; xx++)
				for (int s = qhead[yy * hgw + xx]; s >= 0; s = qlink[s])
				{
					double dx = px[s] - x, dy = py[s] - y;
					double lim = r + (pad ? rad[s] : 0.0);
					if (dx * dx + dy * dy <= lim * lim) outl.Add(s);
				}
		if (y1 > y0 || x1 > x0) outl.Sort();
		return outl;
	}

	// Living bodies whose centre is within r (+ own radius when pad) of (x, y).
	public int[] InRadius(double x, double y, double r, bool pad) { return Circle(x, y, r, pad).ToArray(); }

	// Superset candidates for a GDScript predicate: centre within r + own radius.
	public int[] Candidates(double x, double y, double r) { return Circle(x, y, r, true).ToArray(); }

	public int[] InRect(double x0, double y0, double x1, double y1)
	{
		EnsureQuery();
		var outl = new System.Collections.Generic.List<int>();
		double ax = Math.Min(x0, x1), bx = Math.Max(x0, x1), ay = Math.Min(y0, y1), by = Math.Max(y0, y1);
		for (int yy = HY(ay); yy <= HY(by); yy++)
			for (int xx = HX(ax); xx <= HX(bx); xx++)
				for (int s = qhead[yy * hgw + xx]; s >= 0; s = qlink[s])
					if (px[s] >= ax && px[s] <= bx && py[s] >= ay && py[s] <= by) outl.Add(s);
		outl.Sort();
		return outl.ToArray();
	}

	// Living bodies within `width` (+ own radius) of the segment (railgun / beams), ascending slot.
	public int[] InLine(double x0, double y0, double x1, double y1, double width)
	{
		double pad = width + 32.0;
		int[] c = InRect(Math.Min(x0, x1) - pad, Math.Min(y0, y1) - pad, Math.Max(x0, x1) + pad, Math.Max(y0, y1) + pad);
		double dx = x1 - x0, dy = y1 - y0;
		double L2 = dx * dx + dy * dy;
		var outl = new System.Collections.Generic.List<int>();
		foreach (int s in c)
		{
			double t = L2 > 0 ? ((px[s] - x0) * dx + (py[s] - y0) * dy) / L2 : 0.0;
			if (t < 0.0 || t > 1.0) continue;
			double qx = x0 + dx * t - px[s], qy = y0 + dy * t - py[s];
			double lim = width + rad[s];
			if (qx * qx + qy * qy <= lim * lim) outl.Add(s);
		}
		return outl.ToArray();
	}

	// Living bodies in a cone (apex x,y; unit dir; cos of the half angle; range), ascending slot.
	public int[] InCone(double x, double y, double dirx, double diry, double cosHalf, double range)
	{
		var outl = new System.Collections.Generic.List<int>();
		foreach (int s in Circle(x, y, range, true))
		{
			double dx = px[s] - x, dy = py[s] - y;
			double l = Math.Sqrt(dx * dx + dy * dy);
			if (l <= rad[s] || (dx * dirx + dy * diry) >= cosHalf * l) outl.Add(s);
		}
		return outl.ToArray();
	}

	// Nearest living body with d^2 <= r^2 (ties: the higher slot, `<=`), skipping `exclude`. -1 if none.
	public int Nearest(double x, double y, double r, int[] exclude)
	{
		int best = -1;
		double bd = r * r;
		foreach (int s in Circle(x, y, r, false))
		{
			if (exclude != null && exclude.Length > 0 && Array.IndexOf(exclude, s) >= 0) continue;
			double dx = px[s] - x, dy = py[s] - y;
			double d2 = dx * dx + dy * dy;
			if (d2 <= bd) { bd = d2; best = s; }
		}
		return best;
	}

	// Up to n nearest living bodies within r, nearest first (ties: lower slot).
	public int[] NearestN(double x, double y, int n, double r)
	{
		var c = Circle(x, y, r, false);
		var keys = new double[c.Count];
		var vals = c.ToArray();
		for (int k = 0; k < vals.Length; k++)
		{
			double dx = px[vals[k]] - x, dy = py[vals[k]] - y;
			keys[k] = dx * dx + dy * dy;
		}
		Array.Sort(keys, vals);   // stable enough: vals started ascending; equal keys keep a deterministic order
		int m = Math.Min(n, vals.Length);
		var o = new int[m];
		Array.Copy(vals, o, m);
		return o;
	}

	// Number of living bodies within r of (x, y).
	public int Density(double x, double y, double r) { return Circle(x, y, r, false).Count; }

	// Centre of the living body with the most neighbours within r (ties: the
	// closest to the Core, then the lower slot). Couriers excluded? No: every body.
	[MethodImpl(MethodImplOptions.AggressiveOptimization)]
	public Vector2 Densest(double r)
	{
		EnsureQuery();
		int best = -1, bn = -1;
		double bd = double.PositiveInfinity;
		double rr = r * r;
		int reach = (int)Math.Ceiling(r / HCELL);
		for (int s = 0; s < cap; s++)
		{
			if (live[s] == 0) continue;
			int hx = HX(px[s]), hy = HY(py[s]), n = 0;
			for (int yy = Math.Max(0, hy - reach); yy <= Math.Min(hgw - 1, hy + reach); yy++)
				for (int xx = Math.Max(0, hx - reach); xx <= Math.Min(hgw - 1, hx + reach); xx++)
					for (int j = qhead[yy * hgw + xx]; j >= 0; j = qlink[j])
					{
						double dx = px[j] - px[s], dy = py[j] - py[s];
						if (dx * dx + dy * dy <= rr) n++;
					}
			double cdx = px[s] - cx, cdy = py[s] - cy;
			double d = cdx * cdx + cdy * cdy;
			if (n > bn || (n == bn && d < bd)) { bn = n; bd = d; best = s; }
		}
		if (best < 0) return new Vector2(float.PositiveInfinity, float.PositiveInfinity);
		return new Vector2((float)px[best], (float)py[best]);
	}

	// Chain hop selection (tesla): from `start`, up to `jumps` hops to the nearest
	// unvisited living body within jumpR. Returns the visited slots in hop order.
	public int[] Chain(int start, int jumps, double jumpR)
	{
		var seen = new System.Collections.Generic.List<int>();
		int cur = start;
		while (cur >= 0 && seen.Count < jumps)
		{
			seen.Add(cur);
			cur = Nearest(px[cur], py[cur], jumpR, seen.ToArray());
		}
		return seen.ToArray();
	}

	// ================================================================ test / profile hooks
	// FNV-1a over the live slots' position/velocity bits (determinism gate).
	public long Checksum()
	{
		ulong h = 1469598103934665603UL;
		for (int s = 0; s < cap; s++)
		{
			if (live[s] == 0) continue;
			h = Mix(h, (ulong)s);
			h = Mix(h, (ulong)BitConverter.DoubleToInt64Bits(px[s]));
			h = Mix(h, (ulong)BitConverter.DoubleToInt64Bits(py[s]));
			h = Mix(h, (ulong)BitConverter.DoubleToInt64Bits(vx[s]));
			h = Mix(h, (ulong)BitConverter.DoubleToInt64Bits(vy[s]));
		}
		return (long)h;
	}

	static ulong Mix(ulong h, ulong v)
	{
		for (int b = 0; b < 8; b++) { h ^= (v >> (8 * b)) & 0xFF; h *= 1099511628211UL; }
		return h;
	}

	// Overlap statistics over living non-courier bodies: [pairs overlapping,
	// mean overlap fraction, max overlap fraction] (pressure / no-overlap gate).
	[MethodImpl(MethodImplOptions.AggressiveOptimization)]
	public double[] OverlapStats()
	{
		EnsureQuery();
		int pairs = 0;
		double sum = 0.0, mx = 0.0;
		for (int s = 0; s < cap; s++)
		{
			if (live[s] == 0 || kc[s] == KC_COURIER) continue;
			int reach = (int)Math.Ceiling((rad[s] + 24.0) / HCELL);
			int hx = HX(px[s]), hy = HY(py[s]);
			for (int yy = Math.Max(0, hy - reach); yy <= Math.Min(hgw - 1, hy + reach); yy++)
				for (int xx = Math.Max(0, hx - reach); xx <= Math.Min(hgw - 1, hx + reach); xx++)
					for (int j = qhead[yy * hgw + xx]; j >= 0; j = qlink[j])
					{
						if (j <= s || kc[j] == KC_COURIER) continue;
						double dx = px[j] - px[s], dy = py[j] - py[s];
						double rr = rad[s] + rad[j];
						double d2 = dx * dx + dy * dy;
						if (d2 >= rr * rr) continue;
						double f = (rr - Math.Sqrt(d2)) / rr;
						pairs++; sum += f; if (f > mx) mx = f;
					}
		}
		return new double[] { pairs, pairs > 0 ? sum / pairs : 0.0, mx };
	}

	public Godot.Collections.Dictionary Stats()
	{
		return new Godot.Collections.Dictionary {
			{ "alive", lastAlive }, { "step_us", stepUs }, { "flow_us", flowUs }, { "flow_rebuilds", FlowRebuilds },
			{ "capacity", cap }, { "pass_us", passUs }, { "buildings", bldCount } };
	}

	// Living bodies' slot list (ascending) — debug / profile.
	public int[] LiveSlots()
	{
		var l = new System.Collections.Generic.List<int>();
		for (int s = 0; s < cap; s++) if (live[s] != 0) l.Add(s);
		return l.ToArray();
	}
}
