"""Small Qt-facing projection of renderer-neutral perception events."""

from __future__ import annotations

from PySide6.QtCore import Property, QObject, Signal, Slot

from aurisia.contracts import Direction, PerceptionEvent


class HudBridge(QObject):
    eventChanged = Signal()
    incomingEvent = Signal(object)

    _direction_labels = {
        Direction.LEFT: "من اليسار",
        Direction.CENTER: "من الأمام",
        Direction.RIGHT: "من اليمين",
        Direction.UNKNOWN: "",
    }

    def __init__(self) -> None:
        super().__init__()
        self.incomingEvent.connect(self.show)
        self._has_event = False
        self._title = ""
        self._icon = ""
        self._accent_color = "#3B82F6"
        self._direction = Direction.UNKNOWN.value
        self._direction_label = ""

    def publish(self, event: PerceptionEvent) -> None:
        """Safely enqueue an event from an inference worker thread."""

        self.incomingEvent.emit(event)

    @Slot(object)
    def show(self, event: PerceptionEvent) -> None:
        self._has_event = True
        self._title = event.title
        self._icon = event.icon
        self._accent_color = event.color
        self._direction = event.direction.value
        self._direction_label = self._direction_labels[event.direction]
        self.eventChanged.emit()

    @Property(bool, notify=eventChanged)
    def hasEvent(self) -> bool:  # noqa: N802 - property name is a QML API
        return self._has_event

    @Property(str, notify=eventChanged)
    def title(self) -> str:
        return self._title

    @Property(str, notify=eventChanged)
    def icon(self) -> str:
        return self._icon

    @Property(str, notify=eventChanged)
    def accentColor(self) -> str:  # noqa: N802 - property name is a QML API
        return self._accent_color

    @Property(str, notify=eventChanged)
    def direction(self) -> str:
        return self._direction

    @Property(str, notify=eventChanged)
    def directionLabel(self) -> str:  # noqa: N802 - property name is a QML API
        return self._direction_label
