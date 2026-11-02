"""Notes for the character fallback. Blender is not assumed to auto-rig.

Meshy's rigging endpoint is used when MESHY_API_KEY is set. This file is the
manual path when that call is unavailable or the provider returns a mesh with
no skin. It is not executed as a fake rig.
"""

MANUAL_STEPS_BLENDER = [
    "Install Blender and set BLENDER_BIN.",
    "File > Import > glTF 2.0 and open the asset's original GLB.",
    "Add > Armature. Name bones to match Godot's humanoid profile: Hips, Spine, Chest, Neck, Head, LeftUpperArm, LeftLowerArm, LeftHand, RightUpperArm, RightLowerArm, RightHand, LeftUpperLeg, LeftLowerLeg, LeftFoot, RightUpperLeg, RightLowerLeg, RightFoot.",
    "Match the mesh in A-pose or T-pose. The pipeline does not invent weights.",
    "Select the body, then the armature, and parent with automatic weights.",
    "Put helmets, vests, gloves, boots, and backpacks on the same armature as separate meshes if they should swap.",
    "Export glTF binary (.glb) with Y up. Leave the original file in place.",
    "Use Reprocess in the dashboard and choose the exported GLB.",
]
