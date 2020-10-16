using System;
using System.Collections;

namespace SpyroScope {
	struct CollisionTerrain {
		Mesh collisionMesh;

		public Vector upperBound = .(float.NegativeInfinity,float.NegativeInfinity,float.NegativeInfinity);
		public Vector lowerBound = .(float.PositiveInfinity,float.PositiveInfinity,float.PositiveInfinity);

		public List<int> waterSurfaceTriangles = new .();
		public List<uint8> collisionTypes = new .();

		public enum Overlay {
			None,
			Flags,
			Deform,
			Water,
			Sound,
			Platform
		}
		public Overlay overlay = .None;

		public struct AnimationGroup {
			public Emulator.Address dataPointer;
			public uint32 start;
			public uint32 count;
			public Vector center;
			public float radius;
			public Mesh[] mesh;

			public void Dispose() {
				DeleteContainerAndItems!(mesh);
			}

			public uint8 CurrentKeyframe {
				get {
					uint8 currentKeyframe = ?;
					Emulator.ReadFromRAM(dataPointer + 2, &currentKeyframe, 1);
					return currentKeyframe;
				}
			}

			public struct KeyframeData {
				public uint8 flag, a, nextKeyframe, b, interpolation, fromState, toState, c;
			}

			public KeyframeData GetKeyframeData(uint8 keyframeIndex) {
				AnimationGroup.KeyframeData keyframeData = ?;
				Emulator.ReadFromRAM(dataPointer + 12 + ((uint32)keyframeIndex) * 8, &keyframeData, 8);
				return keyframeData;
			}
		}
		public AnimationGroup[] animationGroups;

		public void Dispose() {
			if (animationGroups != null) {
				for (let item in animationGroups) {
					item.Dispose();
				}
			}
			delete animationGroups;
			delete collisionMesh;
			delete waterSurfaceTriangles;
			delete collisionTypes;
		}

		public void Reload() mut {
			let vertexCount = Emulator.collisionTriangles.Count * 3;
			Vector[] vertices = new .[vertexCount];
			Vector[] normals = new .[vertexCount];
			Renderer.Color4[] colors = new .[vertexCount];

			collisionTypes.Clear();
			waterSurfaceTriangles.Clear();

			upperBound = .(float.NegativeInfinity,float.NegativeInfinity,float.NegativeInfinity);
			lowerBound = .(float.PositiveInfinity,float.PositiveInfinity,float.PositiveInfinity);

			for (let triangleIndex < Emulator.collisionTriangles.Count) {
				let triangle = Emulator.collisionTriangles[triangleIndex];
				let unpackedTriangle = triangle.Unpack(false);
			
				let normal = Vector.Cross(unpackedTriangle[2] - unpackedTriangle[0], unpackedTriangle[1] - unpackedTriangle[0]);
				Renderer.Color color = .(255,255,255);

				// Terrain as Water
				// Derived from Spyro: Ripto's Rage [8003e694]
				if (triangle.data.z & 0x4000 != 0) {
					waterSurfaceTriangles.Add(triangleIndex);
				}

				if (triangleIndex < Emulator.specialTerrainTriangleCount) {
					let flagInfo = Emulator.collisionFlagsIndices[triangleIndex];

					let flagIndex = flagInfo & 0x3f;
					if (flagIndex != 0x3f) {
						Emulator.Address flagPointer = Emulator.collisionFlagPointerArray[flagIndex];
						uint8 flag = ?;
						Emulator.ReadFromRAM(flagPointer, &flag, 1);

						if (overlay == .Flags) {
							if (flag < 11 /*Emulator.collisionTypes.Count*/) {
								color = Emulator.collisionTypes[flag].color;
							} else {
								color = .(255, 0, 255);
							}
						}

						if (!collisionTypes.Contains(flag)) {
							collisionTypes.Add(flag);
						} 
					}
				}

				for (let vi < 3) {
					let i = triangleIndex * 3 + vi;
					vertices[i] = unpackedTriangle[vi];
					normals[i] = normal;
					colors[i] = color;

					upperBound.x = Math.Max(upperBound.x, vertices[i].x);
					upperBound.y = Math.Max(upperBound.y, vertices[i].y);
					upperBound.z = Math.Max(upperBound.z, vertices[i].z);

					lowerBound.x = Math.Min(lowerBound.x, vertices[i].x);
					lowerBound.y = Math.Min(lowerBound.y, vertices[i].y);
					lowerBound.z = Math.Min(lowerBound.z, vertices[i].z);
				}
			}

			delete collisionMesh;
			collisionMesh = new .(vertices, normals, colors);

			// Delete animations as the new loaded mesh may be incompatible
			if (animationGroups != null) {
				for (let item in animationGroups) {
					item.Dispose();
				}
				DeleteAndNullify!(animationGroups);
			}

			ClearColor();
			ApplyColor();
		}
		
		public void Update() {
			if (animationGroups == null || animationGroups.Count == 0) {
				return; // Nothing to update
			}

			for (let groupIndex < animationGroups.Count) {
				let animationGroup = animationGroups[groupIndex];
				let currentKeyframe = animationGroup.CurrentKeyframe;

				AnimationGroup.KeyframeData keyframeData = animationGroup.GetKeyframeData(currentKeyframe);
				
				let interpolation = (float)keyframeData.interpolation / (256);

				if ((animationGroup.start + animationGroup.count) * 3 > collisionMesh.vertices.Count ||
					keyframeData.fromState >= animationGroup.mesh.Count || keyframeData.toState >= animationGroup.mesh.Count) {
					break; // Don't bother since it picked up garbage data
				}

				for (let i < animationGroup.count * 3) {
					Vector fromVertex = animationGroup.mesh[keyframeData.fromState].vertices[i];
					Vector toVertex = animationGroup.mesh[keyframeData.toState].vertices[i];
					Vector fromNormal = animationGroup.mesh[keyframeData.fromState].normals[i];
					Vector toNormal = animationGroup.mesh[keyframeData.toState].normals[i];

					let vertexIndex = animationGroup.start * 3 + i;
					collisionMesh.vertices[vertexIndex] = fromVertex + (toVertex - fromVertex) * interpolation;
					collisionMesh.normals[vertexIndex] = fromNormal + (toNormal - fromNormal) * interpolation;
				}

				if (overlay == .Deform) {
					Renderer.Color transitionColor = keyframeData.fromState == keyframeData.toState ? .(255,128,0) : .((.)((1 - interpolation) * 255), (.)(interpolation * 255), 0);
					for (let i < animationGroup.count * 3) {
						let vertexIndex = animationGroup.start * 3 + i;
						collisionMesh.colors[vertexIndex] = transitionColor;
					}
				}
			}

			collisionMesh.Update();
		}

		public void Draw(bool wireframe) {
			if (collisionMesh == null) {
				return;
			}

			Renderer.SetModel(.Zero, .Identity);

			if (!wireframe) {
				collisionMesh.Draw();
				Renderer.SetTint(.(192,192,192));
			}

			Renderer.BeginWireframe();
			collisionMesh.Draw();

			if (overlay == .Deform && animationGroups != null) {
				Renderer.SetTint(.(255,255,0));
				for	(let animationGroup in animationGroups) {
					for (let mesh in animationGroup.mesh) {
						mesh.Draw();
					}
				}
			}
		}

		public void CycleOverlay() mut {
			// Reset colors before highlighting
			ClearColor();

			switch (overlay) {
				case .None: overlay = .Flags;
				case .Flags: overlay = .Deform;
				case .Deform: overlay = .Water;
				case .Water: overlay = .Sound;
				case .Sound: overlay = .Platform;
				case .Platform: overlay = .None;
			}

			ApplyColor();
		}

		void ApplyColor() {
			switch (overlay) {
				case .None:
				case .Flags: ColorCollisionFlags();
				case .Deform: // Colors applied on update 
				case .Water: ColorWater();
				case .Sound: ColorCollisionSounds();
				case .Platform: ColorPlatforms();
			}

			// Send changed color data
			collisionMesh.Update();
		}

		void ClearColor() {
			for (let i < collisionMesh.colors.Count) {
				collisionMesh.colors[i] = .(255, 255, 255);
			}
		}

		/// Apply colors based on the flag applied on the triangles
		void ColorCollisionFlags() {
			for (int triangleIndex < Emulator.specialTerrainTriangleCount) {
				Renderer.Color color = .(255,255,255);
				let flagInfo = Emulator.collisionFlagsIndices[triangleIndex];

				let flagIndex = flagInfo & 0x3f;
				if (flagIndex != 0x3f) {
					Emulator.Address flagPointer = Emulator.collisionFlagPointerArray[flagIndex];
					uint8 flag = ?;
					Emulator.ReadFromRAM(flagPointer, &flag, 1);

					if (flag < 11 /*Emulator.collisionTypes.Count*/) {
						color = Emulator.collisionTypes[flag].color;
					} else {
						color = .(255, 0, 255);
					}
				}

				for (let vi < 3) {
					let i = triangleIndex * 3 + vi;
					collisionMesh.colors[i] = color;
				}
			}
		}

		/// Apply colors on triangles that are considered water surfaces
		void ColorWater() {
			for (let triangleIndex in waterSurfaceTriangles) {
				for (let vi < 3) {
					let i = triangleIndex * 3 + vi;
					collisionMesh.colors[i] = .(64, 128, 255);
				}
			}
		}

		void ColorCollisionSounds() {
			for (int triangleIndex < Emulator.specialTerrainTriangleCount) {
				Renderer.Color color = .(255,255,255);
				let flagInfo = Emulator.collisionFlagsIndices[triangleIndex];

				// Terrain Collision Sound
				// Derived from Spyro: Ripto's Rage [80034f50]
				let collisionSound = flagInfo >> 6;

				switch (collisionSound) {
					case 1: color = .(255,128,128);
					case 2: color = .(128,255,128);
					case 3: color = .(128,128,255);
				}

				for (let vi < 3) {
					let i = triangleIndex * 3 + vi;
					collisionMesh.colors[i] = color;
				}
			}
		}

		void ColorPlatforms() {
			for (int triangleIndex < Emulator.collisionTriangles.Count) {
				let normal = Vector.Cross(
					collisionMesh.vertices[triangleIndex * 3 + 2] - collisionMesh.vertices[triangleIndex * 3 + 0],
					collisionMesh.vertices[triangleIndex * 3 + 1] - collisionMesh.vertices[triangleIndex * 3 + 0]
				);

				VectorInt normalInt = normal.ToVectorInt();
				// (GTE) Outer Product of 2 Vectors has its
				// Shift Fraction bit enabled so that it
				// shifts the final value by 12 bits to the right
				normalInt.x = normalInt.x >> 12;
				normalInt.y = normalInt.y >> 12;
				normalInt.z = normalInt.z >> 12;

				// Derived from Spyro: Ripto's Rage [8002cda0]
				var slopeDirection = normalInt;
				slopeDirection.z = 0;
				let slope = EMath.Atan2(normalInt.z, (.)EMath.VectorLength(slopeDirection));

				if (Math.Round(slope) < 0x17) { // Derived from Spyro: Ripto's Rage [80035e44]
					for (let vi < 3) {
						let i = triangleIndex * 3 + vi;
						collisionMesh.colors[i] = .(128,255,128);
					}
				}
			}
		}
	}
}
