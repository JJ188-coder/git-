#!/usr/bin/env python3
"""Calculate word error rate for an English reference and hypothesis."""

import argparse
import re
from pathlib import Path


def words(value: str) -> list[str]:
    return re.findall(r"[a-z0-9]+(?:'[a-z]+)?", value.lower())


def main() -> int:
    parser = argparse.ArgumentParser(description="Measure English transcript WER")
    parser.add_argument("reference", type=Path, help="human-correct reference text")
    parser.add_argument("hypothesis", type=Path, help="recognized transcript text")
    args = parser.parse_args()

    reference = words(args.reference.read_text(encoding="utf-8"))
    hypothesis = words(args.hypothesis.read_text(encoding="utf-8"))
    if not reference:
        parser.error("reference transcript contains no English words")

    rows, columns = len(reference), len(hypothesis)
    previous = list(range(columns + 1))
    for row in range(1, rows + 1):
        current = [row] + [0] * columns
        for column in range(1, columns + 1):
            current[column] = min(
                previous[column] + 1,
                current[column - 1] + 1,
                previous[column - 1] + (reference[row - 1] != hypothesis[column - 1]),
            )
        previous = current

    errors = previous[-1]
    print(f"WER: {errors / rows:.2%}")
    print(f"Errors: {errors}")
    print(f"Reference words: {rows}")
    print(f"Recognized words: {columns}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
