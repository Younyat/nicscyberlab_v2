from dataclasses import dataclass, field
from typing import Any, Dict, List


@dataclass
class Scenario:
    name: str
    description: str | None = None
    raw: Dict[str, Any] = field(default_factory=dict)


@dataclass
class IndustrialScenario:
    name: str
    data: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ToolConfig:
    instance: str
    tools: List[Dict[str, Any]] = field(default_factory=list)

