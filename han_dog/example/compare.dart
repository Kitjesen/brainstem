import 'dart:convert';
import 'dart:io';

import 'package:han_dog_brain/han_dog_brain.dart';

void main() {
  final a = load("sample/case1_real.json");
  writeHistory(a, 'sample/case1_real_history.txt');
  final b = load("sample/case1.json");
  writeHistory(b, 'sample/case1_history.txt');
}

List<List<History>> load(String path) {
  final file = File(path);
  final str = file.readAsStringSync();
  final lines = str.trim().split('\n');
  final data = lines
      .map(jsonDecode)
      .map((e) => (e as List).cast<double>())
      .toList();
  final allHistories = <List<History>>[];
  for (final d in data) {
    final obsList = splitObs5(d);
    final historyList = obsList.map(obsToHistory).toList();
    allHistories.add(historyList);
  }
  return allHistories;
}

List<List<double>> splitObs5(List<double> data) {
  final obsList = <List<double>>[];
  for (var i = 0; i < data.length; i += 57) {
    final obs = data.sublist(i, i + 57);
    obsList.add(obs);
  }
  return obsList;
}

History obsToHistory(List<double> obs) => .new(
  gyroscope: .new(obs[0], obs[1], obs[2]),
  projectedGravity: .new(obs[3], obs[4], obs[5]),
  command: .walk(.new(obs[6], obs[7], obs[8])),
  jointPosition: .fromList(obs.sublist(9, 25)),
  jointVelocity: .fromList(obs.sublist(25, 41)),
  action: .fromList(obs.sublist(41, 57)),
  nextAction: .zero(),
);

void writeHistory(List<List<History>> allHistories, String path) {
  final file = File(path);
  file.writeAsStringSync('');
  for (var i = 0; i < allHistories.length; i++) {
    allHistories[i];
    file.writeAsStringSync(
      '------------ History $i -----------\n',
      mode: FileMode.append,
    );
    // for (final history in historyList) {
    //   file.writeAsStringSync('$history\n', mode: FileMode.append);
    // }
    final history = allHistories[i].last;
    file.writeAsStringSync('$history\n', mode: FileMode.append);
  }
}
