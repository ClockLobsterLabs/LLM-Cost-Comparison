"""Validators that reproduce the corruption checks from validate-data.py."""

from collections import defaultdict
from typing import Any


def _is_blank(value: Any) -> bool:
    """True if value is None, empty, or the string 'None'."""
    return value is None or (isinstance(value, str) and value.strip() in ("", "None"))


def find_constant_prompt_tokens(
    rows: list[dict[str, Any]],
    variance_groups: list[str],
    min_group_size: int = 3,
) -> list[tuple[tuple[str, ...], int, int]]:
    """Detect the Session 6b corruption signature: prompt_tokens is constant within groups.

    Returns a list of (group_key, distinct_values, group_size) tuples for suspicious groups.
    """
    groups: dict[tuple[str, ...], list[Any]] = defaultdict(list)
    for row in rows:
        if _is_blank(row.get("prompt_tokens")):
            continue
        key = tuple(str(row.get(g, "")) for g in variance_groups)
        groups[key].append(row["prompt_tokens"])

    corrupt: list[tuple[tuple[str, ...], int, int]] = []
    for key, tokens in groups.items():
        distinct = {str(t) for t in tokens}
        if len(tokens) >= min_group_size and len(distinct) <= 1:
            corrupt.append((key, len(distinct), len(tokens)))
    return corrupt


def find_task_id_leaking_method_names(
    rows: list[dict[str, Any]],
    task_col: str,
    method_names: set[str],
    known_tasks: set[str],
) -> list[str]:
    """Detect rows where the task column has been overwritten with a method name."""
    leaked: list[str] = []
    for row in rows:
        task = str(row.get(task_col, ""))
        if task and task not in known_tasks and task in method_names:
            leaked.append(task)
    return leaked


def find_empty_required_values(
    rows: list[dict[str, Any]],
    col: str,
    status_col: str = "status",
    required_status: str = "success",
) -> int:
    """Count rows with an empty required value on a successful result."""
    return sum(
        1
        for row in rows
        if row.get(status_col) == required_status and _is_blank(row.get(col))
    )


def validate_csv_signature(
    rows: list[dict[str, Any]],
    variance_groups: list[str] | None = None,
    task_col: str | None = None,
    method_names: set[str] | None = None,
    known_tasks: set[str] | None = None,
    required_cols: list[str] | None = None,
) -> tuple[list[str], list[str]]:
    """Run legacy corruption checks and return (errors, warnings)."""
    errors: list[str] = []
    warnings: list[str] = []

    if variance_groups:
        constant = find_constant_prompt_tokens(rows, variance_groups)
        for key, distinct, count in constant[:5]:
            errors.append(
                f"CORRUPTION SIGNATURE — prompt_tokens is constant in group {key}: "
                f"{distinct} distinct value(s) across {count} row(s)"
            )

    if task_col and method_names and known_tasks:
        leaked = find_task_id_leaking_method_names(rows, task_col, method_names, known_tasks)
        if leaked:
            errors.append(f"task_id contains method names: {sorted(set(leaked))}")

    if required_cols:
        for col in required_cols:
            empty = find_empty_required_values(rows, col)
            if empty:
                warnings.append(f"{empty} success rows have empty '{col}'")

    return errors, warnings
