defmodule OpentelemetryCommanded.Aggregate do
  @moduledoc false

  require OpenTelemetry.Tracer

  import OpentelemetryCommanded.Util

  alias OpenTelemetry.{Tracer, Span}

  def setup do
    :telemetry.attach(
      {__MODULE__, :start},
      [:commanded, :aggregate, :execute, :start],
      &__MODULE__.handle_start/4,
      []
    )

    :telemetry.attach(
      {__MODULE__, :stop},
      [:commanded, :aggregate, :execute, :stop],
      &__MODULE__.handle_stop/4,
      []
    )

    :telemetry.attach(
      {__MODULE__, :exception},
      [:commanded, :aggregate, :execute, :exception],
      &__MODULE__.handle_exception/4,
      []
    )
  end

  def handle_start(_event, _, meta, _) do
    context = meta.execution_context
    trace_headers = decode_headers(context.metadata["trace_ctx"])
    :otel_propagator.text_map_extract(trace_headers)

    attributes = [
      "command.type": struct_name(context.command),
      "command.handler": context.handler,
      "aggregate.uuid": meta.aggregate_uuid,
      "aggregate.version": meta.aggregate_version,
      application: meta.application,
      "causation.id": context.causation_id,
      "correlation.id": context.correlation_id,
      "aggregate.function": context.function,
      "aggregate.lifespan": context.lifespan
    ]

    Tracer.start_span("commanded:aggregate:execute", %{
      kind: :consumer,
      attributes: attributes
    })
  end

  def handle_stop(_event, _measurements, meta, _) do
    events = Map.get(meta, :events, [])
    Tracer.set_attribute(:"event.count", Enum.count(events))
    Tracer.end_span()
  end

  def handle_exception(_event, _, %{kind: kind, reason: reason, stacktrace: stacktrace}, _) do
    ctx = Tracer.current_span_ctx()

    exception = Exception.normalize(kind, reason, stacktrace)
    Span.record_exception(ctx, exception, stacktrace)
    Span.set_status(ctx, OpenTelemetry.status(:error, ""))

    Tracer.end_span()
  end
end
