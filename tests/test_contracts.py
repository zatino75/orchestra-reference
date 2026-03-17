# tests/test_contracts.py
import inspect
from app.core.store import store
from app.tasks.registry import run_task


def test_store_required_methods_exist():
    required = [
        "pick_next_runnable",
        "mark_picked",
        "mark_running",
        "mark_succeeded",
        "mark_dead",
        "save_result",
        "save_error",
    ]
    missing = [m for m in required if not callable(getattr(store, m, None))]
    assert not missing, f"Missing store methods: {missing}"


def test_run_task_signature_has_task_name_and_payload():
    sig = str(inspect.signature(run_task))
    assert "task_name" in sig and "payload" in sig, f"Unexpected run_task signature: {sig}"
