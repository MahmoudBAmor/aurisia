from __future__ import annotations

import ast
import unittest
from pathlib import Path


class ServiceBoundaryTests(unittest.TestCase):
    def test_services_do_not_import_other_service_implementations(self) -> None:
        services_root = Path("src/aurisia/services")
        violations: list[str] = []

        for path in services_root.rglob("*.py"):
            relative = path.relative_to(services_root)
            current_service = relative.parts[0] if len(relative.parts) > 1 else None
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            for node in ast.walk(tree):
                imported_modules: list[str] = []
                if isinstance(node, ast.Import):
                    imported_modules.extend(alias.name for alias in node.names)
                elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                    imported_modules.append(node.module)
                for module in imported_modules:
                    prefix = "aurisia.services."
                    if not module.startswith(prefix):
                        continue
                    target_service = module[len(prefix) :].split(".", maxsplit=1)[0]
                    if target_service != current_service:
                        violations.append(f"{path}: imports {module}")

        self.assertEqual(violations, [], "\n".join(violations))

    def test_transport_contract_is_versioned(self) -> None:
        proto = Path("contracts/proto/aurisia/v1/aurisia.proto").read_text(encoding="utf-8")

        self.assertIn("package aurisia.v1;", proto)
        self.assertIn("rpc ListDevices", proto)
        self.assertIn("service SpeechRecognition", proto)
        self.assertIn("service PerceptionFusion", proto)


if __name__ == "__main__":
    unittest.main()
