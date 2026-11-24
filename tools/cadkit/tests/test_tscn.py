import numpy as np

from cadkit.tscn import NodePath, SName, Scene, Xform, fmt, grab_box


def test_scene_text_has_resources_nodes_and_node_paths():
    s = Scene("Toggle", script="res://src/interact/switch_lever.gd")
    s.set(".", swing_deg=80.0, pivot=NodePath("Pivot"), source=SName("sonar"))
    s.node("Pivot", props={"transform": Xform(origin=(0, 0, 0.02))})
    s.node("Bat", parent="Pivot", instance="res://assets/models/kit/x/bat.glb")
    grab_box(s, ".", (0.1, 0.2, 0.05), (0, 0, 0.025))
    text = s.text()
    assert text.startswith("[gd_scene format=3]\n")
    assert '[node name="Toggle" type="Node3D" node_paths=PackedStringArray("pivot")]' in text
    assert 'pivot = NodePath("Pivot")' in text and 'source = &"sonar"' in text
    assert '[node name="Bat" parent="Pivot" instance=ExtResource("2")]' in text
    assert "collision_layer = 2" in text and "size = Vector3(0.1, 0.2, 0.05)" in text
    assert text.count("[ext_resource") == 2


def test_properties_can_be_set_after_resources_are_made():
    s = Scene("A")
    noise = s.sub("Resource", "noise", {"max_intensity": 0.1})
    s.set(".", noise_profile=noise)
    assert 'noise_profile = SubResource("noise")' in s.text()


def test_xform_writes_the_basis_row_by_row():
    # Local X = world X, local Y = world Z, local Z = world -Y: Godot wants rows, the frame is given as columns.
    x = Xform.frame((1, 0, 0), (0, 0, 1), (0, -1, 0), (0, 0, 0.5))
    assert fmt(x) == "Transform3D(1, 0, 0, 0, 0, -1, 0, 1, 0, 0, 0, 0.5)"


def test_xform_composes_like_a_parent_and_child():
    parent = Xform.frame((0, 0, -1), (0, 1, 0), (1, 0, 0), (1, 2, 3))
    child = Xform(origin=(1, 0, 0))
    assert np.allclose((parent @ child).origin, (1, 2, 2))
    assert np.allclose(parent.apply((0, 0, 1)), (2, 2, 3))
