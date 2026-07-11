from __future__ import annotations

from pathlib import Path
from typing import Any

from pipelines.common.io_utils import read_json, write_json


class StateStore:
    def __init__(self, state_file: Path | str) -> None:
        self.state_file = state_file
        self._state = read_json(state_file)

    def get_source(self, source_name: str) -> dict[str, Any]:
        return self._state.get(source_name, {})

    def upsert_source(self, source_name: str, payload: dict[str, Any]) -> None:
        self._state[source_name] = {**self.get_source(source_name), **payload}
        write_json(self._state, self.state_file)

    @property
    def state(self) -> dict[str, Any]:
        return self._state
