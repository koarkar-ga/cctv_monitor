import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../services/hikvision_service.dart';

class AdvancedSeeker extends StatefulWidget {
  final Player player;
  final List<RecordingSegment> events;
  final DateTime startTime;
  final DateTime endTime;
  final Function(double)? onSeekUpdate;
  final Function(double, Offset)?
  onHoverUpdate; // New: Hover callback with position

  const AdvancedSeeker({
    super.key,
    required this.player,
    required this.events,
    required this.startTime,
    required this.endTime,
    this.onSeekUpdate,
    this.onHoverUpdate,
  });

  @override
  _AdvancedSeekerState createState() => _AdvancedSeekerState();
}

class _AdvancedSeekerState extends State<AdvancedSeeker> {
  double _dragValue = -1.0;
  bool _isDragging = false;
  double _hoverValue = -1.0;
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.player.stream.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = widget.player.state.duration;

        return LayoutBuilder(
          builder: (context, constraints) {
            return MouseRegion(
              onEnter: (event) => setState(() => _isHovering = true),
              onExit: (event) {
                setState(() {
                  _isHovering = false;
                  _hoverValue = -1.0;
                });
                // Only hide preview if we aren't dragging
                if (widget.onHoverUpdate != null && !_isDragging) {
                  widget.onHoverUpdate!(-1.0, Offset.zero);
                }
              },
              onHover: (event) {
                final double value =
                    (event.localPosition.dx / constraints.maxWidth).clamp(
                      0.0,
                      1.0,
                    );
                setState(() => _hoverValue = value);
                if (widget.onHoverUpdate != null) {
                  widget.onHoverUpdate!(value, event.localPosition);
                }
              },
              child: GestureDetector(
                onHorizontalDragStart: (details) =>
                    setState(() => _isDragging = true),
                onHorizontalDragUpdate: (details) {
                  final double value =
                      (details.localPosition.dx / constraints.maxWidth).clamp(
                        0.0,
                        1.0,
                      );
                  setState(() {
                    _dragValue = value;
                    _hoverValue = value; // Keep hover synced with drag
                  });
                  if (widget.onSeekUpdate != null) {
                    widget.onSeekUpdate!(value);
                  }
                  // Keep preview updated during drag
                  if (widget.onHoverUpdate != null) {
                    widget.onHoverUpdate!(value, details.localPosition);
                  }
                },
                onHorizontalDragEnd: (details) async {
                  if (duration != Duration.zero) {
                    await widget.player.seek(duration * _dragValue);
                    await widget.player.play();
                  }
                  setState(() {
                    _isDragging = false;
                    _dragValue = -1.0;
                    _isHovering = false; // Hide preview after drop
                  });
                  if (widget.onHoverUpdate != null) {
                    widget.onHoverUpdate!(-1.0, Offset.zero);
                  }
                },
                onTapDown: (details) async {
                  final double value =
                      (details.localPosition.dx / constraints.maxWidth).clamp(
                        0.0,
                        1.0,
                      );
                  if (duration != Duration.zero) {
                    await widget.player.seek(duration * value);
                    await widget.player.play();
                  }
                },
                child: Container(
                  height: 40,
                  width: double.infinity,
                  color: Colors.transparent,
                  child: CustomPaint(
                    painter: SeekerPainter(
                      position: position,
                      duration: duration,
                      events: widget.events,
                      startTime: widget.startTime,
                      endTime: widget.endTime,
                      isDragging: _isDragging,
                      dragValue: _dragValue,
                      isHovering: _isHovering,
                      hoverValue: _hoverValue,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class SeekerPainter extends CustomPainter {
  final Duration position;
  final Duration duration;
  final List<RecordingSegment> events;
  final DateTime startTime;
  final DateTime endTime;
  final bool isDragging;
  final double dragValue;
  final bool isHovering;
  final double hoverValue;

  SeekerPainter({
    required this.position,
    required this.duration,
    required this.events,
    required this.startTime,
    required this.endTime,
    required this.isDragging,
    required this.dragValue,
    required this.isHovering,
    required this.hoverValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    // 1. Draw Background Bar
    final centerY = size.height / 2;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), paint);

    // 2. Draw Motion/Recording Events (Yellow/Orange bars)
    final eventPaint = Paint()
      ..color = Colors.orangeAccent.withOpacity(0.8)
      ..strokeWidth = 8;

    final totalRangeMs = endTime.difference(startTime).inMilliseconds;
    if (totalRangeMs > 0) {
      for (RecordingSegment event in events) {
        final startMs = event.start.difference(startTime).inMilliseconds;
        final endMs = event.end.difference(startTime).inMilliseconds;

        final startX = (startMs / totalRangeMs) * size.width;
        final endX = (endMs / totalRangeMs) * size.width;

        canvas.drawLine(
          Offset(startX.clamp(0, size.width), centerY),
          Offset(endX.clamp(0, size.width), centerY),
          eventPaint,
        );
      }
    }

    // 3. Draw Played Progress
    final progressPaint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    if (duration != Duration.zero) {
      final double progressX =
          (position.inMilliseconds / duration.inMilliseconds) * size.width;
      canvas.drawLine(
        Offset(0, centerY),
        Offset(progressX, centerY),
        progressPaint,
      );

      // 4. Draw Thumb (Playhead)
      final thumbPaint = Paint()..color = Colors.white;
      final double thumbX = isDragging ? dragValue * size.width : progressX;
      canvas.drawCircle(Offset(thumbX, centerY), 6, thumbPaint);
    }

    // 5. Draw Hover Indicator
    if (isHovering && hoverValue >= 0) {
      final hoverPaint = Paint()
        ..color = Colors.white54
        ..strokeWidth = 1;
      final double hvX = hoverValue * size.width;
      canvas.drawLine(
        Offset(hvX, centerY - 10),
        Offset(hvX, centerY + 10),
        hoverPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SeekerPainter oldDelegate) => true;
}
