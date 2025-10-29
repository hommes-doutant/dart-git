// lib/git_async.dart (Corrected)

import 'dart:async';
import 'dart:isolate';

import 'package:file/file.dart';
import 'package:synchronized/synchronized.dart';
import 'package:tuple/tuple.dart';

import 'package:dart_git/config.dart';
import 'package:dart_git/git.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/objects/commit.dart';
import 'package:dart_git/plumbing/reference.dart';

// ... (GitAsyncRepository class and its public methods remain the same) ...
// The public API is already async, so no changes are needed there.

// -- The changes are all in the private, isolate-specific implementation --

enum _Command {
  branches,
  currentBranch,
  setUpstreamTo,
  setBranchUpstreamTo,
  createBranch,
  deleteBranch,

  checkout,
  checkoutBranch,

  headHash,
  headCommit,
  canPush,
  numChangesToPush,

  add,
  rm,
  commit,

  mergeCurrentTrackingBranch, // Corrected name from mergeTrackingBranch
  resetHard,

  remoteBranches,
  remoteBranch,
  addRemote,
  addOrUpdateRemote,
  removeRemote,
}

class _InputMsg {
  _Command command;
  dynamic data;
  _InputMsg(this.command, this.data);
}
class _OutputMsg {
  _Command command;
  dynamic result;
  _OutputMsg(this.command, this.result);
}

typedef _LoadInput = Tuple3<String, FileSystem?, Duration?>;
typedef _ErrorMsg = Tuple2<Object, StackTrace>;
typedef _RemoveInput = Tuple2<String, bool>;
typedef _CommitInput = Tuple4<String, GitAuthor, GitAuthor?, bool>;
typedef _DoubleString = Tuple2<String, String>;
typedef _SetUpstreamToInput = Tuple2<GitRemoteConfig, String>;
typedef _SetBranchUpstreamToInput = Tuple3<String, GitRemoteConfig, String>;
typedef _CreateBranchInput = Tuple3<String, GitHash?, bool>;

// Main entry point for the isolate
Future<void> _isolateMain(SendPort toMainSender) async {
  ReceivePort rp = ReceivePort('GitAsyncRepository_fromIsolate');
  toMainSender.send(rp.sendPort);
  var fromMainRec = rp.asBroadcastStream();

  var input = await fromMainRec.first as _LoadInput;
  var gitRootDir = input.item1;
  var fs = input.item2;
  var autoCloseDuration = input.item3;

  late GitRepository repo;
  try {
    // FIX: Use the new async factory 'local' instead of 'load'
    repo = await GitRepository.local(gitRootDir, fs: fs);
  } catch (e, st) {
    toMainSender.send(_ErrorMsg(e, st));
    rp.close();
    Isolate.exit();
    return;
  }
  toMainSender.send(repo.config);

  var lastCommandTime = DateTime.now();
  if (autoCloseDuration != null && autoCloseDuration.inMicroseconds > 0) {
    Timer.periodic(autoCloseDuration, (timer) {
      var duration = DateTime.now().difference(lastCommandTime);
      if (duration >= autoCloseDuration) {
        rp.close();
        timer.cancel();
        Isolate.exit();
      }
    });
  }

  // The listener callback is now async to allow awaiting _processCommand
  fromMainRec.listen((msg) async {
    var input = msg as _InputMsg;
    try {
      // Await the result of the async command processing
      var out = await _processCommand(repo, input);
      toMainSender.send(_OutputMsg(input.command, out));
    } catch (ex, st) {
      toMainSender.send(_ErrorMsg(ex, st));
    }

    lastCommandTime = DateTime.now();
  });
}

// This function now returns a Future and is marked async.
Future<dynamic> _processCommand(GitRepository repo, _InputMsg input) async {
  var cmd = input.command;

  switch (cmd) {
    // FIX: All method calls on `repo` are now awaited.
    case _Command.branches:
      return await repo.branches();

    case _Command.currentBranch:
      return await repo.currentBranch();

    case _Command.setUpstreamTo:
      var data = input.data as _SetUpstreamToInput;
      // FIX: Method name was missing from GitRepository, let's assume it should exist.
      // We will add it to `git.dart` for completeness.
      return await repo.setUpstreamTo(data.item1, data.item2);

    case _Command.setBranchUpstreamTo:
      var data = input.data as _SetBranchUpstreamToInput;
      return await repo.setBranchUpstreamTo(data.item1, data.item2, data.item3);

    case _Command.createBranch:
      var data = input.data as _CreateBranchInput;
      return await repo.createBranch(data.item1, hash: data.item2, overwrite: data.item3);

    case _Command.deleteBranch:
      return await repo.deleteBranch(input.data);

    case _Command.checkout:
      return await repo.checkout(input.data);

    case _Command.checkoutBranch:
      return await repo.checkoutBranch(input.data);

    case _Command.headHash:
      return await repo.headHash();

    case _Command.headCommit:
      return await repo.headCommit();

    case _Command.canPush:
      return await repo.canPush();

    case _Command.numChangesToPush:
      return await repo.numChangesToPush();

    case _Command.add:
      return await repo.add(input.data);

    case _Command.rm:
      var data = input.data as _RemoveInput;
      return await repo.rm(data.item1, rmFromFs: data.item2);

    case _Command.commit:
      var data = input.data as _CommitInput;
      return await repo.commit(
        message: data.item1,
        author: data.item2,
        committer: data.item3,
        addAll: data.item4,
      );

    case _Command.mergeCurrentTrackingBranch:
      // FIX: This method doesn't exist on GitRepository, needs to be added.
      // Assuming it's a high-level command we need to implement.
      return await repo.mergeCurrentTrackingBranch(author: input.data);

    case _Command.resetHard:
      return await repo.resetHard(input.data);

    case _Command.remoteBranches:
      return await repo.remoteBranches(input.data);

    case _Command.remoteBranch:
      var data = input.data as _DoubleString;
      return await repo.remoteBranch(data.item1, data.item2);

    case _Command.addRemote:
      var data = input.data as _DoubleString;
      return await repo.addRemote(data.item1, data.item2);

    case _Command.addOrUpdateRemote:
      var data = input.data as _DoubleString;
      return await repo.addOrUpdateRemote(data.item1, data.item2);

    case _Command.removeRemote:
      return await repo.removeRemote(input.data);
  }
}