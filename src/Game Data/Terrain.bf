using System;
using System.Collections;
using System.Threading;

namespace SpyroScope {
	class Terrain {
		Mesh mesh;
		public Vector upperBound = .(float.NegativeInfinity,float.NegativeInfinity,float.NegativeInfinity);
		public Vector lowerBound = .(float.PositiveInfinity,float.PositiveInfinity,float.PositiveInfinity);

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

		public bool wireframe;
		public List<int> waterSurfaceTriangles = new .() ~ delete _;
		public List<uint8> collisionTypes = new .() ~ delete _;

		public enum Overlay {
			None,
			Flags,
			Deform,
			Water,
			Sound,
			Platform
		}
		public Overlay overlay = .None;

		public ~this() {
			if (animationGroups != null) {
				for (let item in animationGroups) {
					item.Dispose();
				}
			}
			delete animationGroups;
			delete mesh;
		}

		public void Reload() {
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

			delete mesh;
			mesh = new .(vertices, normals, colors);

			// Delete animations as the new loaded mesh may be incompatible
			if (animationGroups != null) {
				for (let item in animationGroups) {
					item.Dispose();
				}
				delete animationGroups;
				animationGroups = null;
			}

			ClearColor();
			ApplyColor();
		}

		public void ReloadAnimationGroups() {
			uint32 count = ?;
			Emulator.ReadFromRAM(Emulator.collisionModifyingDataPointers[(int)Emulator.rom] - 4, &count, 4);
			if (count == 0) {
				return;
			}
			animationGroups = new .[count];

			let collisionModifyingGroupPointers = scope Emulator.Address[count];
			Emulator.ReadFromRAM(Emulator.collisionModifyingPointerArrayAddress, &collisionModifyingGroupPointers[0], 4 * count);

			for (let groupIndex < count) {
				let animationGroup = &animationGroups[groupIndex];
				animationGroup.dataPointer = collisionModifyingGroupPointers[groupIndex];
				if (animationGroup.dataPointer.IsNull) {
					continue;
				}

				Emulator.ReadFromRAM(animationGroup.dataPointer + 4, &animationGroup.count, 2);
				Emulator.ReadFromRAM(animationGroup.dataPointer + 6, &animationGroup.start, 2);
				
				uint32 triangleDataOffset = ?;
				Emulator.ReadFromRAM(animationGroup.dataPointer + 8, &triangleDataOffset, 4);

				// Analyze the animation
				uint32 keyframeCount = triangleDataOffset >> 3 - 1; // / 8
				uint8 highestUsedState = 0;
				for (let keyframeIndex < keyframeCount) {
					(uint8 fromState, uint8 toState) s = ?;
					Emulator.ReadFromRAM(animationGroup.dataPointer + 12 + keyframeIndex * 8 + 5, &s, 2);

					highestUsedState = Math.Max(highestUsedState, s.fromState);
					highestUsedState = Math.Max(highestUsedState, s.toState);
				}

				Vector upperBound = .(float.NegativeInfinity,float.NegativeInfinity,float.NegativeInfinity);
				Vector lowerBound = .(float.PositiveInfinity,float.PositiveInfinity,float.PositiveInfinity);

				let stateCount = highestUsedState + 1;
				let groupVertexCount = animationGroup.count * 3;
				animationGroup.mesh = new .[stateCount];
				for (let stateIndex < stateCount) {
					Vector[] vertices = new .[groupVertexCount];
					Vector[] normals = new .[groupVertexCount];
					Renderer.Color4[] colors = new .[groupVertexCount];

					let startTrianglesState = stateIndex * animationGroup.count;
					for (let triangleIndex < animationGroup.count) {
						PackedTriangle packedTriangle = ?;
						Emulator.ReadFromRAM(animationGroup.dataPointer + triangleDataOffset + (startTrianglesState + triangleIndex) * 12, &packedTriangle, 12);
						let unpackedTriangle = packedTriangle.Unpack(true);

						let normal = Vector.Cross(unpackedTriangle[2] - unpackedTriangle[0], unpackedTriangle[1] - unpackedTriangle[0]);
						Renderer.Color color = .(255,255,255);

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
					
					animationGroup.mesh[stateIndex] = new .(vertices, normals, colors);
					animationGroup.center = (upperBound + lowerBound) / 2;
					animationGroup.radius = (upperBound - animationGroup.center).Length();
				}
			}

			ClearColor();
		}

		public void Update() {
			if (mesh == null || mesh.vertices.Count == 0) {
				return; // No mesh to update
			}

			let collisionModifyingPointerArrayAddressOld = Emulator.collisionModifyingPointerArrayAddress;
			Emulator.ReadFromRAM(Emulator.collisionModifyingDataPointers[(int)Emulator.rom], &Emulator.collisionModifyingPointerArrayAddress, 4);
			if (Emulator.collisionModifyingPointerArrayAddress != 0 && collisionModifyingPointerArrayAddressOld != Emulator.collisionModifyingPointerArrayAddress) {
				ReloadAnimationGroups();
			}

			if (animationGroups == null || animationGroups.Count == 0) {
				return; // Nothing to update
			}

			for (let groupIndex < animationGroups.Count) {
				let animationGroup = animationGroups[groupIndex];
				let currentKeyframe = animationGroup.CurrentKeyframe;

				AnimationGroup.KeyframeData keyframeData = animationGroup.GetKeyframeData(currentKeyframe);
				
				let interpolation = (float)keyframeData.interpolation / (256);

				if ((animationGroup.start + animationGroup.count) * 3 > mesh.vertices.Count ||
					keyframeData.fromState >= animationGroup.mesh.Count || keyframeData.toState >= animationGroup.mesh.Count) {
					break; // Don't bother since it picked up garbage data
				}

				for (let i < animationGroup.count * 3) {
					Vector fromVertex = animationGroup.mesh[keyframeData.fromState].vertices[i];
					Vector toVertex = animationGroup.mesh[keyframeData.toState].vertices[i];
					Vector fromNormal = animationGroup.mesh[keyframeData.fromState].normals[i];
					Vector toNormal = animationGroup.mesh[keyframeData.toState].normals[i];

					let vertexIndex = animationGroup.start * 3 + i;
					mesh.vertices[vertexIndex] = fromVertex + (toVertex - fromVertex) * interpolation;
					mesh.normals[vertexIndex] = fromNormal + (toNormal - fromNormal) * interpolation;
				}

				if (overlay == .Deform) {
					Renderer.Color transitionColor = keyframeData.fromState == keyframeData.toState ? .(255,128,0) : .((.)((1 - interpolation) * 255), (.)(interpolation * 255), 0);
					for (let i < animationGroup.count * 3) {
						let vertexIndex = animationGroup.start * 3 + i;
						mesh.colors[vertexIndex] = transitionColor;
					}
				}
			}

			mesh.Update();
		}

		public void Draw() {
			if (mesh == null) {
				return;
			}

			Renderer.SetModel(.Zero, .Identity);
			Renderer.SetTint(.(255,255,255));
			Renderer.BeginSolid();

			if (!wireframe) {
				mesh.Draw();
				Renderer.SetTint(.(128,128,128));
			}

			Renderer.BeginWireframe();
			mesh.Draw();

			if (overlay == .Deform && animationGroups != null) {
				Renderer.SetTint(.(255,255,0));
				for	(let animationGroup in animationGroups) {
					for (let mesh in animationGroup.mesh) {
						mesh.Draw();
					}
				}
			}

			// Restore polygon mode to default
			Renderer.BeginSolid();
		}

		public void CycleOverlay() {
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
		}

		void ClearColor() {
			for (let i < mesh.colors.Count) {
				mesh.colors[i] = .(255, 255, 255);
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
					mesh.colors[i] = color;
				}
			}
		}
		
		/// Apply colors on triangles that are considered water surfaces
		void ColorWater() {
			for (let triangleIndex in waterSurfaceTriangles) {
				for (let vi < 3) {
					let i = triangleIndex * 3 + vi;
					mesh.colors[i] = .(64, 128, 255);
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
					mesh.colors[i] = color;
				}
			}
		}

		void ColorPlatforms() {
			for (int triangleIndex < Emulator.collisionTriangles.Count) {
				let normal = Vector.Cross(
					mesh.vertices[triangleIndex * 3 + 2] - mesh.vertices[triangleIndex * 3 + 0],
					mesh.vertices[triangleIndex * 3 + 1] - mesh.vertices[triangleIndex * 3 + 0]
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
						mesh.colors[i] = .(128,255,128);
					}
				}
			}
		}
	}
}
