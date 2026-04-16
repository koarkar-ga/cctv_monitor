import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class RecordingCalendar extends StatefulWidget {
  final DateTime selectedDate;
  final Set<int> recordedDays;
  final Function(DateTime) onDateSelected;
  final Function(DateTime) onMonthChanged;
  final bool isLoading;

  const RecordingCalendar({
    super.key,
    required this.selectedDate,
    required this.recordedDays,
    required this.onDateSelected,
    required this.onMonthChanged,
    this.isLoading = false,
  });

  @override
  State<RecordingCalendar> createState() => _RecordingCalendarState();
}

class _RecordingCalendarState extends State<RecordingCalendar> {
  late DateTime _viewMonth;

  @override
  void initState() {
    super.initState();
    _viewMonth = DateTime(widget.selectedDate.year, widget.selectedDate.month);
  }

  void _changeMonth(int offset) {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + offset);
    });
    widget.onMonthChanged(_viewMonth);
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(_viewMonth.year, _viewMonth.month);
    final firstDayOffset = DateTime(_viewMonth.year, _viewMonth.month, 1).weekday % 7;

    return Column(
      children: [
        _buildHeader(),
        const SizedBox(height: 12),
        _buildDaysHeader(),
        const SizedBox(height: 8),
        _buildGrid(daysInMonth, firstDayOffset),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white70),
          onPressed: () => _changeMonth(-1),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        Text(
          DateFormat('MMMM yyyy').format(_viewMonth),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: Colors.white70),
          onPressed: () => _changeMonth(1),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Widget _buildDaysHeader() {
    final days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: days
          .map((d) => SizedBox(
                width: 32,
                child: Text(
                  d,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildGrid(int daysInMonth, int firstDayOffset) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: 42, // Fix grid size to avoid jitter
      itemBuilder: (context, index) {
        final day = index - firstDayOffset + 1;
        if (day < 1 || day > daysInMonth) return const SizedBox.shrink();

        final date = DateTime(_viewMonth.year, _viewMonth.month, day);
        final isSelected = DateUtils.isSameDay(date, widget.selectedDate);
        
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final isFuture = date.isAfter(today);

        // Only show record indicator if:
        // 1. It's in the recordedDays set
        // 2. It's not a future date
        // 3. We aren't currently loading new data (to avoid showing stale dots from previous month)
        final actualHasRecord =
            widget.recordedDays.contains(day) && !isFuture && !widget.isLoading;

        return InkWell(
          onTap: () => widget.onDateSelected(date),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.blueAccent
                  : actualHasRecord
                      ? Colors.greenAccent.withOpacity(0.1)
                      : Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? Colors.blueAccent
                    : actualHasRecord
                        ? Colors.greenAccent.withOpacity(0.3)
                        : Colors.transparent,
                width: 1,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (actualHasRecord && !isSelected)
                  Positioned(
                    bottom: 4,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
