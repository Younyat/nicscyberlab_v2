from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional
from app_core.domain.models import Scenario, IndustrialScenario, ToolConfig


class ScenarioRepository(ABC):
    @abstractmethod
    def save(self, scenario: Scenario) -> str:
        ...

    @abstractmethod
    def get(self, name: str) -> Optional[Scenario]:
        ...


class IndustrialScenarioRepository(ABC):
    @abstractmethod
    def save(self, scenario: IndustrialScenario) -> str:
        ...

    @abstractmethod
    def list_all(self) -> List[IndustrialScenario]:
        ...


class ToolsConfigRepository(ABC):
    @abstractmethod
    def save(self, config: ToolConfig) -> str:
        ...

    @abstractmethod
    def list_all(self) -> List[ToolConfig]:
        ...

    @abstractmethod
    def get(self, instance: str) -> Optional[ToolConfig]:
        ...


class ShellRunner(ABC):
    @abstractmethod
    def run(self, cmd: list[str], cwd: str | None = None) -> Dict[str, Any]:
        ...

    @abstractmethod
    def popen(self, cmd: list[str], cwd: str | None = None):
        ...


class OpenStackService(ABC):
    @abstractmethod
    def list_instances(self) -> List[Dict[str, Any]]:
        ...

    @abstractmethod
    def classify_instances(self) -> Dict[str, Any]:
        ...
