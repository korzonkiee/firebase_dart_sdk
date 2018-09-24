// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/abstract_stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/firestore_channel.dart';
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/firestore.pb.dart';
import 'package:grpc/grpc.dart';

/// A Stream that implements the [StreamingWatch] RPC.
///
/// * Once the [WatchStream] has started, any number of [watchQuery] and
/// [unwatchTargetId] calls can be sent to control what changes will be sent
/// from the server for [WatchChanges].
///
/// @see <a
/// href="https://github.com/googleapis/googleapis/blob/master/google/firestore/v1beta1/firestore.proto#L147">firestore.proto</a>
class WatchStream
    extends AbstractStream<ListenRequest, ListenResponse, WatchStreamCallback> {
  /// The empty stream token.
  static const List<int> EMPTY_RESUME_TOKEN = <int>[];

  final RemoteSerializer serializer;

  WatchStream(FirestoreChannel channel, AsyncQueue workerQueue, this.serializer,
      WatchStreamCallback listener)
      : super(
            channel,
            ClientMethod(
              'listen',
              (ListenRequest req) => req.writeToBuffer(),
              (List<int> res) => ListenResponse.fromBuffer(res),
            ),
            workerQueue,
            TimerId.LISTEN_STREAM_CONNECTION_BACKOFF,
            TimerId.LISTEN_STREAM_IDLE,
            listener);

  /// Registers interest in the results of the given query. If the query
  /// includes a [resumeToken] it will be included in the request. Results that
  /// affect the query will be streamed back as [WatchChange] messages that
  /// reference the [targetId] included in query.
  void watchQuery(QueryData queryData) {
    FirestoreApi;
    Assert.hardAssert(isOpen, 'Watching queries requires an open stream');
    final ListenRequest request = ListenRequest.create()
      ..database = serializer.databaseName
      ..addTarget = serializer.encodeTarget(queryData);

    final MapEntry<String, String> labels =
        serializer.encodeListenRequestLabels(queryData);
    if (labels != null) {
      final ListenRequest_LabelsEntry entry = ListenRequest_LabelsEntry.create()
        ..key = labels.key
        ..value = labels.value;

      request.labels.add(entry);
    }

    writeRequest(request.freeze());
  }

  /// Unregisters interest in the results of the query associated with the given
  /// target id.
  void unwatchTarget(int targetId) {
    Assert.hardAssert(isOpen, 'Unwatching targets requires an open stream');

    final ListenRequest request = ListenRequest.create()
      ..database = serializer.databaseName
      ..removeTarget = targetId
      ..freeze();

    writeRequest(request);
  }

  @override
  void onNext(ListenResponse listenResponse) {
    // A successful response means the stream is healthy
    backoff.reset();

    final WatchChange watchChange =
        serializer.decodeWatchChange(listenResponse);
    final SnapshotVersion snapshotVersion =
        serializer.decodeVersionFromListenResponse(listenResponse);
    listener.onWatchChange(snapshotVersion, watchChange);
  }
}

/// A callback interface for the set of events that can be emitted by the
/// [WatchStream]
abstract class WatchStreamCallback extends StreamCallback {
  /// A new change from the watch stream. Snapshot version will ne non-null if
  /// it was set
  void onWatchChange(SnapshotVersion snapshotVersion, WatchChange watchChange);
}