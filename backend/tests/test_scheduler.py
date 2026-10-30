from datetime import date, datetime, time

from app.agent.scheduler import Slot, replan

DAY = date(2026, 10, 30)
NEXT = date(2026, 10, 31)


def slot(task_id, start=None, duration=60, priority="medium", type_="study", position=0):
    return Slot(task_id, f"t{task_id}", type_, priority, duration, start, position)


def moves(placements):
    return {p.task_id: (p.date, p.start) for p in placements}


def test_future_tasks_keep_their_time_by_default():
    tasks = [slot(1, time(9)), slot(2, time(14))]
    assert replan(DAY, tasks, now=datetime(2026, 10, 30, 8, 0)) == []


def test_passed_task_moves_to_first_gap_after_now_and_around_meetings():
    tasks = [slot(1, time(9)), slot(2, time(11, 30), 30, type_="meeting"), slot(3, time(13))]
    # 11:10 now: #1 (09:00) was missed today; 11:10–12:10 would hit the 11:30 meeting
    result = moves(replan(DAY, tasks, now=datetime(2026, 10, 30, 11, 7)))
    assert result == {1: (DAY, time(12, 0))}


def test_clash_with_kept_task_is_resolved():
    tasks = [slot(1, time(10), 120), slot(2, time(11), 60)]
    result = moves(replan(DAY, tasks, now=datetime(2026, 10, 30, 8)))
    assert result == {2: (DAY, time(12))}


def test_compact_pulls_the_day_earlier_in_priority_order():
    tasks = [slot(1, time(14), 60, "low"), slot(2, time(16), 30, "high"), slot(3, time(12), 30, type_="meeting")]
    result = moves(replan(DAY, tasks, now=datetime(2026, 10, 30, 10, 2), compact=True))
    assert result == {2: (DAY, time(10, 5)), 1: (DAY, time(10, 35))}


def test_missed_tasks_fill_today_and_overflow_to_tomorrow():
    tasks = [slot(1, time(20), 60)]
    missed = [(slot(7, time(9), 90, "high"), date(2026, 10, 29)), (slot(8, None, 60, "low"), date(2026, 10, 28))]
    result = moves(replan(DAY, tasks, missed=missed, now=datetime(2026, 10, 30, 18, 0), window=(time(8), time(22))))
    # 18:00–19:30 for #7; #8 needs 60 min but 19:30–20:30 hits #1 and 21:00–22:00 fits
    assert result == {7: (DAY, time(18)), 8: (DAY, time(21))}

    result = moves(replan(DAY, tasks, missed=missed, now=datetime(2026, 10, 30, 20, 30)))
    assert result == {1: (DAY, time(20, 30)), 7: (NEXT, None), 8: (NEXT, None)}


def test_anytime_tasks_are_left_alone_and_past_day_overflows():
    tasks = [slot(1, None), slot(2, time(9))]
    result = moves(replan(DAY, tasks, now=datetime(2026, 10, 31, 9, 0)))
    assert result == {2: (NEXT, None)}


def test_future_day_uses_window_start():
    tasks = [slot(1, time(6), 30)]  # before the window → treated as needing a slot? no: 06:00 < 08:00 cursor
    result = moves(replan(NEXT, tasks, now=datetime(2026, 10, 30, 12, 0)))
    assert result == {1: (NEXT, time(8))}
