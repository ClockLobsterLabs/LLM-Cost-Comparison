"""Experiment implementations and runner factory."""

from __future__ import annotations

from typing import TYPE_CHECKING

from llm_cost_comparison.experiments.appraisal import AppraisalExperiment
from llm_cost_comparison.experiments.base import REGISTRY, Experiment, ExperimentRunner, register
from llm_cost_comparison.experiments.compression import CompressionExperiment
from llm_cost_comparison.experiments.output_verbosity import OutputVerbosityExperiment
from llm_cost_comparison.experiments.speed import SpeedExperiment
from llm_cost_comparison.experiments.tokenizer import TokenizerEfficiencyExperiment

if TYPE_CHECKING:
    from llm_cost_comparison.clients.base import LLMClient
    from llm_cost_comparison.core.models import Catalog
    from llm_cost_comparison.storage.repository import MeasurementRepository

__all__ = [
    "REGISTRY",
    "AppraisalExperiment",
    "CompressionExperiment",
    "Experiment",
    "ExperimentRunner",
    "OutputVerbosityExperiment",
    "SpeedExperiment",
    "TokenizerEfficiencyExperiment",
    "register",
]


def create_runner(
    catalog: Catalog,
    client: LLMClient,
    repository: MeasurementRepository,
) -> ExperimentRunner:
    """Return a runner with all built-in experiments pre-registered."""
    return ExperimentRunner(catalog, client, repository)
