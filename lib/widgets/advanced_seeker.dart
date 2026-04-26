import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../services/hikvision_service.dart';

class AdvancedSeeker extends StatefulWidget {
  final Player player;
  final List<RecordingSegment> events;
  final DateTime startTime;
  final DateTime endTime;
  final RecordingSegment? activeSegment;
  final Function(double)? onSeekUpdate;
  final Function(double, Offset)?
  onHoverUpdate; // New: Hover callback with position

  const AdvancedSeeker({
    super.key,
    required this.player,
    required this.events,
    required this.startTime,
    required this.endTime,
    this.activeSegment,
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
                onHorizontalDragStart: (details) {
                  setState(() {
                    _isDragging = true;
                    _dragValue = (details.localPosition.dx / constraints.maxWidth)
                        .clamp(0.0, 1.0);
                    _hoverValue = _dragValue;
                  });
                  // Show preview immediately on start
                  if (widget.onHoverUpdate != null) {
                    widget.onHoverUpdate!(_dragValue, details.localPosition);
                  }
                },
                onHorizontalDragUpdate: (details) {
                  final double value =
                      (details.localPosition.dx / constraints.maxWidth).clamp(
                    0.0,
                    1.0,
                  );
                  setState(() {
                    _dragValue = value;
                    _hoverValue = value;
                  });
                  // Only update the preview/hover while dragging, don't seek yet
                  if (widget.onHoverUpdate != null) {
                    widget.onHoverUpdate!(value, details.localPosition);
                  }
                },
                onHorizontalDragEnd: (details) {
                  // Commit the seek when the user releases
                  if (widget.onSeekUpdate != null && _dragValue >= 0) {
                    widget.onSeekUpdate!(_dragValue);
                  }
                  setState(() {
                    _isDragging = false;
                    _dragValue = -1.0;
                    _isHovering = false;
                  });
                  if (widget.onHoverUpdate != null) {
                    widget.onHoverUpdate!(-1.0, Offset.zero);
                  }
                },
                onTapDown: (details) {
                  final double value =
                      (details.localPosition.dx / constraints.maxWidth).clamp(
                    0.0,
                    1.0,
                  );
                  // Update hover/preview on tap so user sees feedback
                  if (widget.onHoverUpdate != null) {
                    widget.onHoverUpdate!(value, details.localPosition);
                    // Hide after a short delay
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (!_isDragging && mounted) {
                        widget.onHoverUpdate!(-1.0, Offset.zero);
                      }
                    });
                  }
                  if (widget.onSeekUpdate != null) {
                    widget.onSeekUpdate!(value);
                  }
                },
                child: Container(
                  height: 60, // Increased hit area
                  width: double.infinity,
                  color: Colors.transparent,
                  child: CustomPaint(
                    painter: SeekerPainter(
                      position: position,
                      duration: duration,
                      events: widget.events,
                      startTime: widget.startTime,
                      endTime: widget.endTime,
                      activeSegment: widget.activeSegment,
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
  final RecordingSegment? activeSegment;

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
    this.activeSegment,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Background Bar (No Record Area)
    final centerY = size.height / 2;
    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), bgPaint);

    // 2. Draw Recording Segments (Solid Green/Cyan)
    final eventPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 10;

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

    if (totalRangeMs > 0) {
      double globalProgressX = 0;
      
      if (activeSegment != null && duration != Duration.zero) {
        final absolutePlayheadMs = activeSegment!.start.difference(startTime).inMilliseconds + position.inMilliseconds;
        globalProgressX = (absolutePlayheadMs / totalRangeMs) * size.width;
      }

      // 3. Draw Played Progress (Inside the active segment)
      if (activeSegment != null && duration != Duration.zero) {
        final startMs = activeSegment!.start.difference(startTime).inMilliseconds;
        final startX = (startMs / totalRangeMs) * size.width;
        
        final progressPaint = Paint()
          ..color = Colors.blueAccent
          ..strokeWidth = 10 // Same as eventPaint to overlay
          ..strokeCap = StrokeCap.butt;

        canvas.drawLine(
          Offset(startX, centerY),
          Offset(globalProgressX, centerY),
          progressPaint,
        );
      }

      // 4. Draw Thumb (Playhead) - Brighter and Larger
      final thumbPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final thumbBorderPaint = Paint()
        ..color = Colors.blueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
        
      final double thumbX = isDragging ? dragValue * size.width : globalProgressX;
      
      if (activeSegment != null || isDragging) {
        canvas.drawCircle(Offset(thumbX, centerY), 8, thumbPaint);
        canvas.drawCircle(Offset(thumbX, centerY), 8, thumbBorderPaint);
      }
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
