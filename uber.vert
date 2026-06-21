layout(location = 6) out vec3 PositionWrapped;
out flat int isFontDraw;



vec4 lovrmain() {
  vec4 posWorld = Transform * VertexPosition;
  PositionWorld = posWorld.xyz;
  vec3 TransformScale = vec3(length(Transform[0].xyz), length(Transform[1].xyz), length(Transform[2].xyz));
  PositionWrapped = VertexPosition.xyz * TransformScale;
  isFontDraw = (VertexPosition.z == 0. && Normal.x == 0. && Normal.y == 0. && Normal.z == 0.) ? 1 : 0;
  return ViewProjection * posWorld;
}
