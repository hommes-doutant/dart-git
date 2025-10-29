// FILE: test/merge_base_test.dart
// Code base adapted from go-git/plumbing/object/merge_base_test.go

/* ... (comment block remains the same) ... */

import 'package:test/test.dart';

import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/objects/object.dart';
import 'lib.dart';

var revisionIndex = <String, GitHash>{
  'master': GitHash('dce0e0c20d701c3d260146e443d6b3b079505191'),
  'feature': GitHash('d1b0093698e398d596ef94d646c4db37e8d1e970'),
  'dev': GitHash('25ca6c810c08482d61113fbcaaada38bb59093a8'),
  'M': GitHash('bb355b64e18386dbc3af63dfd09c015c44cbd9b6'),
  'N': GitHash('d64b894762ab5f09e2b155221b90c18bd0637236'),
  'A': GitHash('29740cfaf0c2ee4bb532dba9e80040ca738f367c'),
  'B': GitHash('2c84807970299ba98951c65fe81ebbaac01030f0'),
  'AB': GitHash('31a7e081a28f149ee98ffd13ba1a6d841a5f46fd'),
  'P': GitHash('ff84393134864cf9d3a9853a81bde81778bd5805'),
  'C': GitHash('8b72fabdc4222c3ff965bc310ded788c601c50ed'),
  'D': GitHash('14777cf3e209334592fbfd0b878f6868394db836'),
  'CD1': GitHash('4709e13a3cbb300c2b8a917effda776e1b8955c7'),
  'CD2': GitHash('38468e274e91e50ffb637b88a1954ab6193fe974'),
  'S': GitHash('628f1a42b70380ed05734bf01b468b46206ef1ea'),
  'G': GitHash('d1b0093698e398d596ef94d646c4db37e8d1e970'),
  'Q': GitHash('dce0e0c20d701c3d260146e443d6b3b079505191'),
  'GQ1': GitHash('ccaaa99c21dad7e9f392c36ae8cb72dc63bed458'),
  'GQ2': GitHash('806824d4778e94fe7c3244e92a9cd07090c9ab54'),
  'A^': GitHash('31a7e081a28f149ee98ffd13ba1a6d841a5f46fd'),
  'A^^': GitHash('bb355b64e18386dbc3af63dfd09c015c44cbd9b6'),
  'A^^^': GitHash('8d08dd1388b82dd354cb43918d83da86c76b0978'),
  'N^': GitHash('b6e1fc8dad4f1068fb42774ec5fc65c065b2c312'),
};

class Test {
  final List<String> input;
  final List<String> output;
  final String name;

  Test(this.input, this.output, this.name);
}

var data = [
  Test(['M', 'N'], [], 'NoAncestorsWhenNoCommonHistory'),
  Test(['A', 'B'], ['AB'], 'CommonAncestorInMergedOrphans'),
  Test(['A', 'A'], ['A'], 'MergeBaseWithSelf'),
  Test(['Q', 'N'], ['N'], 'MergeBaseWithAncestor'),
  Test(['C', 'D'], ['CD1', 'CD2'], 'DoubleCommonAncestorInCrossMerge'),
  Test(['G', 'Q'], ['GQ1', 'GQ2'], 'DoubleCommonInSubFeatureBranches')
];

var independentData = [
  Test(['A'], ['A'], 'OnlyOne'),
  Test(['A', 'A', 'A'], ['A'], 'OnlyRepeated'),
  Test(['A', 'A', 'M', 'M', 'N'], ['A', 'N'], 'RepeatedAncestors'),
  Test(['S', 'G', 'P'], ['S', 'G'], 'BeyondShortcut'),
  Test(['CD1', 'CD2', 'M', 'N'], ['CD1', 'CD2'], 'BeyondShortcutBis'),
  Test(['C', 'D', 'M', 'N'], ['C', 'D'], 'PairOfAncestors'),
  Test(['C', 'G', 'dev', 'M', 'N'], ['C', 'G', 'dev'], 'AcrossCrossMerges'),
  Test(['A', 'A^', 'A', 'M', 'N'], ['A', 'N'], 'ChangingOrderRepetition'),
  Test(['A^^^', 'A^', 'A^^', 'A', 'N'], ['A', 'N'], 'ChangingOrder'),
  Test(['A', 'CD1'], ['CD1'], 'ParentChild'),
];

class ATest {
  final List<String> input;
  final bool output;
  final String name;

  ATest(this.input, this.output, this.name);
}

var ancestorData = [
  ATest(['A^^', 'A'], true, 'OnlyOne'),
  ATest(['A', 'A^^'], false, 'OnlyOneRev'),
  ATest(['M', 'G'], true, 'BeyondMerges'),
  ATest(['G', 'M'], false, 'BeyondMergesRev'),
  ATest(['A', 'A'], true, 'AncestorSame'),
  ATest(['M', 'N'], false, 'AncestorUnrelated'),
  ATest(['N', 'M'], false, 'AncestorUnrelatedRev'),
];

void main() {
  late String gitDir;

  setUpAll(() async {
    gitDir = await openFixture('test/data/git-merge-base.tar.gz');
  });

  // Change 1: Move helper functions inside main()
  Future<List<GitCommit>> commitsFromRevs(
      GitRepository repo, List<String> revs) async {
    var commits = <GitCommit>[];
    for (var rev in revs) {
      var hash = revisionIndex[rev]!;
      var result = await repo.objStorage.readCommit(hash);
      commits.add(result);
    }
    return commits;
  }

  int sortByHash(GitObject a, GitObject b) {
    return a.hash.toString().compareTo(b.hash.toString());
  }

  group('MergeBase', () {
    for (var t in data) {
      test(t.name, () async {
        expect(t.input.length, 2);

        var repo = await GitRepository.local(gitDir);
        var commits = await commitsFromRevs(repo, t.input);
        expect(commits.length, 2);

        var result = await repo.mergeBase(commits[0], commits[1]);
        result.sort(sortByHash);

        var output = await commitsFromRevs(repo, t.output);
        output.sort(sortByHash);

        var actual = result.map((r) => r.hash).toList();
        var expected = output.map((r) => r.hash).toList();

        expect(actual, expected);
      });
    }
  });

  group('Independents', () {
    for (var t in independentData) {
      test(t.name, () async {
        var repo = await GitRepository.local(gitDir);
        var commits = await commitsFromRevs(repo, t.input);

        var actual = await repo.independents(commits);
        var expected = await commitsFromRevs(repo, t.output);

        expect(actual.toSet(), expected.toSet());
      });
    }
  });

  group('Ancestor', () {
    for (var t in ancestorData) {
      test(t.name, () async {
        var repo = await GitRepository.local(gitDir);
        var commits = await commitsFromRevs(repo, t.input);

        var actual = await repo.isAncestor(commits[0], commits[1]);
        expect(actual, t.output);
      });
    }
  });
}