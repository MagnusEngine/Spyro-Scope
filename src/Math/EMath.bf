using System;

/*
	The following below that are derived from the game are most likely partially implemented
	for the parts they are needed for. And the variable names given here are not likely used
	in the original source code. They are just reasonable placeholder names to help organize
	and understand the MIPS assembly code as a high-level language.
*/

namespace SpyroScope {
	static class EMath {
		// Derived from Spyro: Ripto's Rage [80061e5c]
		public const uint16[130] AtanLookup =
			.(0x0,0x14,0x29,0x3d,0x51,0x66,0x7a,0x8e,0xa3,0xb7,
			0xcb,0xe0,0xf4,0x108,0x11c,0x130,0x144,0x158,0x16c,0x180,
			0x194,0x1a8,0x1bc,0x1d0,0x1e3,0x1f7,0x20b,0x21e,0x232,0x245,
			0x258,0x26c,0x27f,0x292,0x2a5,0x2b8,0x2cb,0x2de,0x2f1,0x303,
			0x316,0x328,0x33b,0x34d,0x35f,0x372,0x384,0x396,0x3a8,0x3b9,
			0x3cb,0x3dd,0x3ee,0x400,0x411,0x422,0x433,0x444,0x455,0x466,
			0x477,0x488,0x498,0x4a9,0x4b9,0x4c9,0x4d9,0x4e9,0x4f9,0x509,
			0x519,0x529,0x538,0x548,0x557,0x566,0x575,0x584,0x593,0x5a2,
			0x5b1,0x5bf,0x5ce,0x5dc,0x5ea,0x5f9,0x607,0x615,0x623,0x630,
			0x63e,0x64c,0x659,0x666,0x674,0x681,0x68e,0x69b,0x6a8,0x6b5,
			0x6c1,0x6ce,0x6da,0x6e7,0x6f3,0x6ff,0x70c,0x718,0x724,0x72f,
			0x73b,0x747,0x752,0x75e,0x769,0x775,0x780,0x78b,0x796,0x7a1,
			0x7ac,0x7b7,0x7c1,0x7cc,0x7d7,0x7e1,0x7eb,0x7f6,0x800,0x0);

		// Derived from Spyro: Ripto's Rage [8001b4b8]
		public static int32 Atan2(int32 adjacentLeg, int32 oppositeLeg) {
			var leg1 = Math.Abs(adjacentLeg);
			var leg2 = Math.Abs(oppositeLeg);

			if (leg1 > leg2) {
				Swap!(leg1,leg2);
			}
			if (leg2 == 0) {
				leg2 = 1;
			}

			var cosined = (leg1 << 14) / leg2;

			bool flipSign;
			int offsetValue;
			if (adjacentLeg < 0) {
				if (oppositeLeg < 0) {
					flipSign = oppositeLeg < adjacentLeg;
					offsetValue = flipSign ? 0x3000 : 0x2000;
				} else {
					flipSign = oppositeLeg < -adjacentLeg;
					offsetValue = flipSign ? 0x2000 : 0x1000;
				}
			} else {
				if (oppositeLeg < 0) {
					flipSign = oppositeLeg > -adjacentLeg;
					offsetValue = flipSign ? 0 : 0x3000;
				} else {
					flipSign = oppositeLeg > adjacentLeg;
					offsetValue = flipSign ? 0x1000 : 0;
				}
			}

			let fraction = cosined & 0x7f;
			let lookupIndex = cosined >> 7;
			int32 theta = AtanLookup[lookupIndex];
			if (fraction != 0) {
				theta += (fraction * (AtanLookup[lookupIndex + 1] - theta)) >> 7;
			}
			if (flipSign) {
				theta = -theta;
			}
			theta += (.)offsetValue;
			return ((0x20 + theta) >> 6) & 0xff;
		}

		// Derived from Spyro: Ripto's Rage [80066478]
		public const uint32[192] VectorLengthLookup = .(
			0x1000,0x101f,0x103f,0x105e,0x107e,0x109c,0x10bb,0x10da,0x10f8,0x1116,0x1134,0x1152,
			0x116f,0x118c,0x11a9,0x11c6,0x11e3,0x1200,0x121c,0x1238,0x1254,0x1270,0x128c,0x12a7,
			0x12c2,0x12de,0x12f9,0x1314,0x132e,0x1349,0x1364,0x137e,0x1398,0x13b2,0x13cc,0x13e6,
			0x1400,0x1419,0x1432,0x144c,0x1465,0x147e,0x1497,0x14b0,0x14c8,0x14e1,0x14f9,0x1512,
			0x152a,0x1542,0x155a,0x1572,0x158a,0x15a2,0x15b9,0x15d1,0x15e8,0x1600,0x1617,0x162e,
			0x1645,0x165c,0x1673,0x1689,0x16a0,0x16b7,0x16cd,0x16e4,0x16fa,0x1710,0x1726,0x173c,
			0x1752,0x1768,0x177e,0x1794,0x17aa,0x17bf,0x17d5,0x17ea,0x1800,0x1815,0x182a,0x183f,
			0x1854,0x1869,0x187e,0x1893,0x18a8,0x18bd,0x18d1,0x18e6,0x18fa,0x190f,0x1923,0x1938,
			0x194c,0x1960,0x1974,0x1988,0x199c,0x19b0,0x19c4,0x19d8,0x19ec,0x1a00,0x1a13,0x1a27,
			0x1a3a,0x1a4e,0x1a61,0x1a75,0x1a88,0x1a9b,0x1aae,0x1ac2,0x1ad5,0x1ae8,0x1afb,0x1b0e,
			0x1b21,0x1b33,0x1b46,0x1b59,0x1b6c,0x1b7e,0x1b91,0x1ba3,0x1bb6,0x1bc8,0x1bdb,0x1bed,
			0x1c00,0x1c12,0x1c24,0x1c36,0x1c48,0x1c5a,0x1c6c,0x1c7e,0x1c90,0x1ca2,0x1cb4,0x1cc6,
			0x1cd8,0x1ce9,0x1cfb,0x1d0d,0x1d1e,0x1d30,0x1d41,0x1d53,0x1d64,0x1d76,0x1d87,0x1d98,
			0x1daa,0x1dbb,0x1dcc,0x1ddd,0x1dee,0x1e00,0x1e11,0x1e22,0x1e33,0x1e43,0x1e54,0x1e65,
			0x1e76,0x1e87,0x1e98,0x1ea8,0x1eb9,0x1eca,0x1eda,0x1eeb,0x1efb,0x1f0c,0x1f1c,0x1f2d,
			0x1f3d,0x1f4e,0x1f5e,0x1f6e,0x1f7e,0x1f8f,0x1f9f,0x1faf,0x1fbf,0x1fcf,0x1fdf,0x1fef);

		// Derived from Spyro: Ripto's Rage [8001ba20]
		public static uint32 VectorLength(VectorInt vector) {
			var vector;

			let usedBits = (uint32)(Math.Abs(vector.x) | Math.Abs(vector.y) | Math.Abs(vector.z));
			int bitCount = CountSignBits(usedBits);

			int shift = 18 - (.)bitCount;
			int makeupShift = 0;
			if (0 < shift) {
				vector.x = vector.x >> (shift & 0x1f);
				vector.y = vector.y >> (shift & 0x1f);
				vector.z = vector.z >> (shift & 0x1f);
				makeupShift = shift;
			}

			let vectorSum = vector.LengthSq();
			uint32 length = 0;
			if (vectorSum != 0) {
				bitCount = CountSignBits((.)vectorSum);
				let shiftCount = (bitCount & 0xfe) - 24;
				let extendedSum = shiftCount < 0 ? vectorSum >> (-shiftCount & 0x1f) : vectorSum << (shiftCount & 0x1f);
				length = (uint32)((int32)VectorLengthLookup[extendedSum - 0x40] << (((0x1f - (bitCount & 0xfe)) >> 1) & 0x1f)) >> 0xc;
				if (length != 0) {
					length = (.)((int32)length + (((int32)(vectorSum - length * length) / (int32)(length + 1)) >> 1));
				}
			}

			return length << (makeupShift & 0x1f);
		}

		/// (GTE) Count Leading-Zeroes/Ones (Sign Bits)
		static int CountSignBits(uint32 value) {
			for (int i < 32) {
				if ((0x80000000 >> i) & value != 0) {
					return i;
				}
			}
			return 32;
		}
	}
}
