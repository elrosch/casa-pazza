import 'package:casa_pazza/src/features/widget/home_widget_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses widget launch URIs', () {
    expect(
      WidgetRequest.fromUri(Uri.parse('casapazza://add-task')),
      isA<AddTaskRequest>(),
    );
    final edit = WidgetRequest.fromUri(
      Uri.parse('casapazza://edit-task?id=abc123'),
    );
    expect(edit, isA<EditTaskRequest>());
    expect((edit! as EditTaskRequest).taskId, 'abc123');
    expect(WidgetRequest.fromUri(Uri.parse('casapazza://edit-task')), isNull);
    final scan = WidgetRequest.fromUri(Uri.parse('casapazza://scan'));
    expect(scan, isA<ScanRequest>());
    expect(scan!.route, '/shopping');
    expect(const AddTaskRequest().route, '/tasks');
    final voice = WidgetRequest.fromUri(Uri.parse('casapazza://voice'));
    expect(voice, isA<VoiceRequest>());
    expect(voice!.route, '/tasks');
    expect(WidgetRequest.fromUri(Uri.parse('casapazza://tasks')), isNull);
    expect(WidgetRequest.fromUri(null), isNull);
  });
}
