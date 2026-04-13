import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TERRAFORM_MAIN = ROOT / "terraform" / "main.tf"
OUTPUT = ROOT / "docs" / "terraform-modules.md"


MODULE_BLOCK_RE = re.compile(r'module\s+"(?P<name>[^"]+)"\s*{(?P<body>.*?)}', re.DOTALL)
ATTRIBUTE_RE = re.compile(r"^\s*(?P<key>[A-Za-z0-9_]+)\s*=\s*(?P<value>.+?)\s*$", re.MULTILINE)
MODULE_REF_RE = re.compile(r"module\.([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)")


def parse_modules(text: str):
    modules = []
    for match in MODULE_BLOCK_RE.finditer(text):
        body = match.group("body")
        attrs = {}
        refs = []
        for attr in ATTRIBUTE_RE.finditer(body):
            key = attr.group("key")
            value = attr.group("value").strip()
            attrs[key] = value
            refs.extend((dep, out) for dep, out in MODULE_REF_RE.findall(value))
        modules.append(
            {
                "name": match.group("name"),
                "source": attrs.get("source", "").strip('"'),
                "inputs": {k: v for k, v in attrs.items() if k != "source"},
                "refs": refs,
            }
        )
    return modules


def build_mermaid(modules):
    lines = ["graph TD"]
    for module in modules:
        label = f"{module['name']}\\n{module['source']}"
        lines.append(f'    {module["name"]}["{label}"]')
    for module in modules:
        for dep, output in module["refs"]:
            lines.append(f"    {dep} -->|{output}| {module['name']}")
    return "\n".join(lines)


def build_markdown(modules):
    mermaid = build_mermaid(modules)
    lines = [
        "# Terraform Module Graph",
        "",
        "Generated from `terraform/main.tf`.",
        "",
        "```mermaid",
        mermaid,
        "```",
        "",
        "## Module Wiring",
        "",
        "| Module | Source | Inputs |",
        "|---|---|---|",
    ]
    for module in modules:
        inputs = "<br>".join(f"`{k}` = `{v}`" for k, v in module["inputs"].items()) or "-"
        lines.append(f"| `{module['name']}` | `{module['source']}` | {inputs} |")
    return "\n".join(lines) + "\n"


def main():
    modules = parse_modules(TERRAFORM_MAIN.read_text())
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(build_markdown(modules))


if __name__ == "__main__":
    main()
