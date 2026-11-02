class PipelineError(Exception):
    """Base error for pipeline failures that should be shown to the user."""


class ConfigError(PipelineError):
    """A required program or credential is missing or invalid."""


class ProviderError(PipelineError):
    """An external generation service returned an error."""


class ValidationFailure(PipelineError):
    """An asset failed a quality check."""
