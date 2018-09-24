// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/abstract_stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/firestore_channel.dart';
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/firestore.pb.dart';
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/write.pb.dart';
import 'package:grpc/grpc.dart';

/// A Stream that implements the [StreamingWrite] RPC.
///
/// * The [StreamingWrite] RPC requires the caller to maintain special
/// [streamToken] state in between calls, to help the server understand which
/// responses the client has processed by the time the next request is made.
/// Every response may contain a [streamToken]; this value must be passed to the
/// next request.
///
/// * After calling [start] on this stream, the next request must be a handshake,
/// containing whatever [streamToken] is on hand. Once a response to this request
/// is received, all pending mutations may be submitted. When submitting multiple
/// batches of mutations at the same time, it's okay to use the same
/// [streamToken] for the calls to [writeMutations].
///
/// @see <a
/// href="https://github.com/googleapis/googleapis/blob/master/google/firestore/v1beta1/firestore.proto#L139">firestore.proto</a>
class WriteStream
    extends AbstractStream<WriteRequest, WriteResponse, WriteStreamCallback> {
  /// The empty stream token.
  static const List<int> EMPTY_STREAM_TOKEN = <int>[];

  final RemoteSerializer _serializer;

  /// Contains last received stream token from the server, used to acknowledge
  /// which responses the client has processed. Stream tokens are opaque
  /// checkpoint markers whose only real value is their inclusion in the next
  /// request.
  ///
  /// * WriteStream implementations manage propagating this value from responses
  /// to the next request.
  ///
  /// NOTE: A null [streamToken] is not allowed: use the empty array for the
  /// unset value.
  List<int> lastStreamToken = EMPTY_STREAM_TOKEN;

  bool _handshakeComplete = false;

  WriteStream(FirestoreChannel channel, AsyncQueue workerQueue,
      this._serializer, WriteStreamCallback listener)
      : super(
            channel,
            ClientMethod(
              'write',
              (WriteRequest req) => req.writeToBuffer(),
              (List<int> res) => WriteResponse.fromBuffer(res),
            ),
            workerQueue,
            TimerId.WRITE_STREAM_CONNECTION_BACKOFF,
            TimerId.WRITE_STREAM_IDLE,
            listener);

  @override
  void start() {
    this._handshakeComplete = false;
    super.start();
  }

  @override
  void tearDown() {
    if (_handshakeComplete) {
      // Send an empty write request to the backend to indicate imminent stream
      // closure. This allows the backend to clean up resources.
      writeMutations(<Mutation>[]);
    }
  }

  /// Tracks whether or not a handshake has been successfully exchanged and the
  /// stream is ready to accept mutations.
  bool get isHandshakeComplete => _handshakeComplete;

  /// Sends an initial [streamToken] to the server, performing the handshake
  /// required to make the [StreamingWrite] RPC work. Subsequent
  /// [writeMutations] calls should wait until a response has been delivered to
  /// [WriteStreamCallback.onHandshakeComplete].
  void writeHandshake() {
    Assert.hardAssert(isOpen, 'Writing handshake requires an opened stream');
    Assert.hardAssert(!_handshakeComplete, 'Handshake already completed');
    // TODO: Support stream resumption. We intentionally do not set the stream
    // token on the handshake, ignoring any stream token we might have.
    final WriteRequest request = WriteRequest.create()
      ..database = _serializer.databaseName;

    writeRequest(request.freeze());
  }

  /// Sends a list of mutations to the Firestore backend to apply
  void writeMutations(List<Mutation> mutations) {
    Assert.hardAssert(isOpen, 'Writing mutations requires an opened stream');
    Assert.hardAssert(_handshakeComplete,
        'Handshake must be complete before writing mutations');
    final WriteRequest request = WriteRequest.create();
    request.streamToken = lastStreamToken;

    for (Mutation mutation in mutations) {
      request.writes.add(_serializer.encodeMutation(mutation));
    }

    writeRequest(request.freeze());
  }

  @override
  void onNext(WriteResponse response) {
    lastStreamToken = response.streamToken;

    if (!_handshakeComplete) {
      // The first response is the handshake response
      _handshakeComplete = true;

      listener.onHandshakeComplete();
    } else {
      // A successful first write response means the stream is healthy,
      // Note, that we could consider a successful handshake healthy, however,
      // the write itself might be causing an error we want to back off from.
      backoff.reset();

      final SnapshotVersion commitVersion =
          _serializer.decodeVersion(response.commitTime);

      final int count = response.writeResults.length;
      final List<MutationResult> results = List<MutationResult>(count);
      for (int i = 0; i < count; i++) {
        final WriteResult result = response.writeResults[i];
        results.add(_serializer.decodeMutationResult(result, commitVersion));
      }
      listener.onWriteResponse(commitVersion, results);
    }
  }
}

/// A callback interface for the set of events that can be emitted by the
/// [WriteStream]
abstract class WriteStreamCallback extends StreamCallback {
  /// The handshake for this write stream has completed
  void onHandshakeComplete();

  /// Response for the last write.
  void onWriteResponse(
      SnapshotVersion commitVersion, List<MutationResult> mutationResults);
}