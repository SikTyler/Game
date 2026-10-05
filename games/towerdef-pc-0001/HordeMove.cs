using System;
using Godot;

// HORDE hot loop (C# port of EnemyStore.move): move + separation + knockback.
// Bit-identical to the GDScript path: vectors are float32 (Godot Vector2,
// real_t = float) and every vector op mirrors Godot's C++ Vector2 (scalar
// doubles cast to float before a vector multiply/divide); scalars are double
// like GDScript float. Operation order is identical. Called from GDScript via
// an instance (GDScript cannot call C# statics); Run() itself is pure static.
[GlobalClass]
public partial class HordeMove : RefCounted
{
	const int F_EXIT = 2;
	const int ACT_BLD = 0, ACT_SHOT = 1, ACT_HIT = 2, ACT_ESCAPE = 3;
	const double SEP_CS = 32.0;
	const int SEP_GW = 96;

	// sc = [dt, frozen, cx, cy, stop_r, r_stop, r_fire, side, cell, accel_k, sep_k, sep_cap, fr, kmax, capacity]
	// Returns [pos, vel, slow_t, slow_m, shock_t, hit_t, taunt_t, cur_s, atk_cd, fire_cd, acts].
	public Godot.Collections.Array Move(int[] order, Vector2[] pos, Vector2[] vel, Vector2[] exit,
		double[] spd, double[] size, int[] kcode, int[] flags,
		double[] slow_t, double[] slow_m, double[] shock_t, double[] hit_t, double[] taunt_t,
		double[] cur_s, double[] atk_cd, double[] fire_cd, byte[] blk, double[] sc)
	{
		int[] acts = Run(order, pos, vel, exit, spd, size, kcode, flags, slow_t, slow_m, shock_t, hit_t,
			taunt_t, cur_s, atk_cd, fire_cd, blk, sc);
		return new Godot.Collections.Array {
			pos, vel, slow_t, slow_m, shock_t, hit_t, taunt_t, cur_s, atk_cd, fire_cd, acts };
	}

	static float Len(Vector2 v) { return MathF.Sqrt(v.X * v.X + v.Y * v.Y); }
	static float Len2(Vector2 v) { return v.X * v.X + v.Y * v.Y; }
	static Vector2 Mul(Vector2 v, double s) { float f = (float)s; return new Vector2(v.X * f, v.Y * f); }
	static Vector2 Div(Vector2 v, double s) { float f = (float)s; return new Vector2(v.X / f, v.Y / f); }
	static Vector2 Add(Vector2 a, Vector2 b) { return new Vector2(a.X + b.X, a.Y + b.Y); }
	static Vector2 Sub(Vector2 a, Vector2 b) { return new Vector2(a.X - b.X, a.Y - b.Y); }
	static Vector2 Norm(Vector2 v)
	{
		float l = v.X * v.X + v.Y * v.Y;
		if (l != 0f) { l = MathF.Sqrt(l); return new Vector2(v.X / l, v.Y / l); }
		return v;
	}

	[ThreadStatic] static int[] _head;
	[ThreadStatic] static int[] _link;

	// kcode: 0 other, 1 courier, 2 ranged. Mutates the arrays in place.
	public static int[] Run(int[] order, Vector2[] pos, Vector2[] vel, Vector2[] exit,
		double[] spd, double[] size, int[] kcode, int[] flags,
		double[] slow_t, double[] slow_m, double[] shock_t, double[] hit_t, double[] taunt_t,
		double[] cur_s, double[] atk_cd, double[] fire_cd, byte[] blk, double[] sc)
	{
		var acts = new System.Collections.Generic.List<int>(64);
		double dt = sc[0];
		bool frozen = sc[1] != 0.0;
		Vector2 center = new Vector2((float)sc[2], (float)sc[3]);
		double stop_r = sc[4], r_stop = sc[5], r_fire = sc[6];
		int side = (int)sc[7];
		double cell = sc[8];
		double accel_k = sc[9], sep_k = sc[10], sep_cap = sc[11], fr = sc[12];
		int kmax = (int)sc[13];
		bool has_b = blk.Length > 0;
		int half = side / 2;
		Vector2[] old = (Vector2[])pos.Clone();
		int gw = SEP_GW;
		double ox = (double)center.X - SEP_CS * gw * 0.5;
		double oy = (double)center.Y - SEP_CS * gw * 0.5;
		bool do_sep = sep_k > 0.0 && order.Length > 1 && !frozen;
		const int reach = 1;
		if (do_sep)
		{
			if (_head == null || _head.Length != gw * gw) _head = new int[gw * gw];
			Array.Fill(_head, -1);
			if (_link == null || _link.Length < pos.Length) _link = new int[pos.Length];
			for (int ri = order.Length - 1; ri >= 0; ri--)
			{
				int q = order[ri];
				Vector2 qp = old[q];
				int gx = (int)Math.Floor(((double)qp.X - ox) / SEP_CS);
				int gy = (int)Math.Floor(((double)qp.Y - oy) / SEP_CS);
				if (gx < 0 || gy < 0 || gx >= gw || gy >= gw) continue;
				int ci = gy * gw + gx;
				_link[q] = _head[ci];
				_head[ci] = q;
			}
		}
		int[] head = _head, link = _link;
		foreach (int e in order)
		{
			Vector2 p = old[e];
			double st = slow_t[e];
			double mult = st > 0.0 ? slow_m[e] : 1.0;
			double st2 = Math.Max(0.0, st - dt);
			slow_t[e] = st2;
			if (st2 <= 0.0) slow_m[e] = 1.0;
			shock_t[e] = Math.Max(0.0, shock_t[e] - dt);
			hit_t[e] = Math.Max(0.0, hit_t[e] - dt);
			if (frozen) continue;
			int k = kcode[e];
			if (k == 1)
			{
				Vector2 to2 = (flags[e] & F_EXIT) != 0 ? exit[e] : p;
				Vector2 dd = Sub(to2, p);
				double stp = spd[e] * mult * dt;
				if ((double)Len(dd) <= stp) { acts.Add(ACT_ESCAPE); acts.Add(e); }
				else pos[e] = Add(p, Mul(Norm(dd), stp));
				continue;
			}
			double taunt = taunt_t[e];
			bool pinned = taunt > 0.0;
			if (pinned) taunt_t[e] = Math.Max(0.0, taunt - dt);
			bool ranged = k == 2;
			double stop = ranged ? r_stop : stop_r;
			Vector2 to_c = Sub(center, p);
			double dist = Len(to_c);
			Vector2 mv = Vector2.Zero;
			int bc = -1;
			if (!pinned && dist > stop + 0.001)
			{
				Vector2 dir = Div(to_c, dist);
				if (has_b)
				{
					Vector2 ahead = Sub(Add(p, Mul(dir, size[e] * 0.5 + 2.0)), center);
					int col = (int)Math.Floor((double)ahead.X / cell + 0.5) + half;
					int row = (int)Math.Floor((double)ahead.Y / cell + 0.5) + half;
					if (col >= 0 && col < side && row >= 0 && row < side && blk[row * side + col] == 1)
						bc = row * side + col;
				}
				if (bc >= 0)
				{
					cur_s[e] = 0.0;
					atk_cd[e] = atk_cd[e] - dt;
					if (atk_cd[e] <= 0.0)
					{
						atk_cd[e] = ranged ? r_fire : 1.0;
						acts.Add(ACT_BLD); acts.Add(e); acts.Add(bc);
					}
				}
				else
				{
					double vmax = spd[e] * mult;
					double cs = Math.Min(vmax, cur_s[e] + vmax * accel_k * dt);
					cur_s[e] = cs;
					mv = Mul(dir, Math.Min(dist - stop, cs * dt));
				}
			}
			else cur_s[e] = 0.0;
			if (do_sep)
			{
				Vector2 push = Vector2.Zero;
				int seen = 0;
				double si = size[e];
				double mi = si * si;
				int cx = (int)Math.Floor(((double)p.X - ox) / SEP_CS);
				int cy = (int)Math.Floor(((double)p.Y - oy) / SEP_CS);
				int y1 = Math.Min(gw - 1, cy + reach), x1 = Math.Min(gw - 1, cx + reach);
				for (int yy = Math.Max(0, cy - reach); yy <= y1; yy++)
				{
					for (int xx = Math.Max(0, cx - reach); xx <= x1; xx++)
					{
						int j = head[yy * gw + xx];
						while (j >= 0 && seen < kmax)
						{
							seen++;
							if (j != e)
							{
								Vector2 dv = Sub(p, old[j]);
								double sj = size[j];
								double rr = (si + sj) * 0.5;
								double d2 = Len2(dv);
								if (d2 < rr * rr)
								{
									double l = Math.Sqrt(d2);
									double w = sj * sj / (mi + sj * sj);
									if (l > 0.0001) push = Add(push, Mul(Div(dv, l), (rr - l) * w));
									else push = Add(push, Mul(new Vector2(e > j ? 1.0f : -1.0f, 0.0f), rr * w));
								}
							}
							j = link[j];
						}
					}
				}
				if (push != Vector2.Zero)
				{
					push = Mul(push, sep_k);
					double cap = si * sep_cap;
					double pl = Len(push);
					if (pl > cap) push = Mul(push, cap / pl);
					mv = Add(mv, push);
				}
			}
			Vector2 kv = vel[e];
			if (kv != Vector2.Zero)
			{
				mv = Add(mv, Mul(kv, dt));
				kv = Mul(kv, fr);
				if ((double)Len2(kv) < 0.01) kv = Vector2.Zero;
				vel[e] = kv;
			}
			Vector2 np = Add(p, mv);
			Vector2 rel = Sub(np, center);
			double nd = Len(rel);
			if (nd < stop && nd > 0.0)
			{
				np = Add(center, Mul(Div(rel, nd), stop));
				nd = stop;
			}
			pos[e] = np;
			if (pinned || bc >= 0) continue;
			if (nd > stop + size[e] * 0.5 + 0.5) continue;
			if (ranged)
			{
				fire_cd[e] = fire_cd[e] - dt;
				if (fire_cd[e] <= 0.0)
				{
					fire_cd[e] = fire_cd[e] + r_fire;
					acts.Add(ACT_SHOT); acts.Add(e);
				}
			}
			else
			{
				atk_cd[e] = atk_cd[e] - dt;
				if (atk_cd[e] <= 0.0)
				{
					atk_cd[e] = 1.0;
					acts.Add(ACT_HIT); acts.Add(e);
				}
			}
		}
		return acts.ToArray();
	}
}
