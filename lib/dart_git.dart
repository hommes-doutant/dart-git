// lib/dart_git.dart (The new public API entry point)

/// A pure Dart, read-only, filesystem-agnostic Git implementation.
///
/// This library provides a high-level API for inspecting a Git repository's state,
/// history, and files without performing any write operations.
library dart_git_reader;

// --- Core Public API ---
// Instead of defining GitRepositoryReader in a separate file,
// you can define it here or, better yet, export it.
// Let's assume you've moved the GitRepositoryReader class from 'dart_git_reader.dart'
// into a new file, say 'lib/reader.dart'.

export 'package:dart_git/reader.dart'; // Exports GitRepositoryReader

// --- Supporting APIs and Data Models ---
export 'package:dart_git/plumbing/git_hash.dart';
export 'package:dart_git/plumbing/objects/commit.dart' show GitAuthor; // Only show GitAuthor
export 'package:dart_git/plumbing/reference.dart' show Reference, HashReference, SymbolicReference, ReferenceName;
export 'package:dart_git/status.dart' show GitStatusResult, GitFileStatus, GitFileStatusType;

// --- Abstractions for Custom Backends ---
export 'package:dart_git/storage/providers/storage_provider.dart';
export 'package:dart_git/storage/providers/storage_handle.dart';

export 'git.dart';
export 'git_async.dart';
export 'plumbing/objects/commit.dart';