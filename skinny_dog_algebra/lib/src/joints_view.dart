extension type const JointsView<T>._(List<T> values) implements Iterable<T> {
  JointsView.fromList(this.values) {
    assert(values.length == 16);
  }
  // dart format off
  factory JointsView(
    T frHip, T frThigh, T frCalf,
    T flHip, T flThigh, T flCalf,
    T rrHip, T rrThigh, T rrCalf,
    T rlHip, T rlThigh, T rlCalf,

    T frFoot,T flFoot, T rrFoot, T rlFoot,
  ) => .fromList([
    frHip,  frThigh, frCalf,
    flHip,  flThigh, flCalf,
    rrHip,  rrThigh, rrCalf,
    rlHip,  rlThigh, rlCalf,

    frFoot, flFoot, rrFoot, rlFoot,
  ]);
  // dart format on

  T get frHip => values[0];
  T get frThigh => values[1];
  T get frCalf => values[2];

  T get flHip => values[3];
  T get flThigh => values[4];
  T get flCalf => values[5];

  T get rrHip => values[6];
  T get rrThigh => values[7];
  T get rrCalf => values[8];

  T get rlHip => values[9];
  T get rlThigh => values[10];
  T get rlCalf => values[11];

  T get frFoot => values[12];
  T get flFoot => values[13];
  T get rrFoot => values[14];
  T get rlFoot => values[15];

  set frHip(T value) => values[0] = value;
  set frThigh(T value) => values[1] = value;
  set frCalf(T value) => values[2] = value;

  set flHip(T value) => values[3] = value;
  set flThigh(T value) => values[4] = value;
  set flCalf(T value) => values[5] = value;

  set rrHip(T value) => values[6] = value;
  set rrThigh(T value) => values[7] = value;
  set rrCalf(T value) => values[8] = value;

  set rlHip(T value) => values[9] = value;
  set rlThigh(T value) => values[10] = value;
  set rlCalf(T value) => values[11] = value;

  set frFoot(T value) => values[12] = value;
  set flFoot(T value) => values[13] = value;
  set rrFoot(T value) => values[14] = value;
  set rlFoot(T value) => values[15] = value;
}

mixin JointsViewMixin<T> {
  List<T> get values;

  T get frHip => values[0];
  T get frThigh => values[1];
  T get frCalf => values[2];

  T get flHip => values[3];
  T get flThigh => values[4];
  T get flCalf => values[5];

  T get rrHip => values[6];
  T get rrThigh => values[7];
  T get rrCalf => values[8];

  T get rlHip => values[9];
  T get rlThigh => values[10];
  T get rlCalf => values[11];

  T get frFoot => values[12];
  T get flFoot => values[13];
  T get rrFoot => values[14];
  T get rlFoot => values[15];

  set frHip(T value) => values[0] = value;
  set frThigh(T value) => values[1] = value;
  set frCalf(T value) => values[2] = value;

  set flHip(T value) => values[3] = value;
  set flThigh(T value) => values[4] = value;
  set flCalf(T value) => values[5] = value;

  set rrHip(T value) => values[6] = value;
  set rrThigh(T value) => values[7] = value;
  set rrCalf(T value) => values[8] = value;

  set rlHip(T value) => values[9] = value;
  set rlThigh(T value) => values[10] = value;
  set rlCalf(T value) => values[11] = value;

  set frFoot(T value) => values[12] = value;
  set flFoot(T value) => values[13] = value;
  set rrFoot(T value) => values[14] = value;
  set rlFoot(T value) => values[15] = value;
}
