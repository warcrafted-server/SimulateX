"""Genera, por cada spec de nivel 80 de wowsims/wotlk, un pequeño programa Go
(en Tools/wowsimcli-src/<paquete>/gen_extractor/main.go, no versionado) que
reconstruye el RaidSimRequest base de esa spec y lo vuelca a JSON.

No transcribe manualmente los valores de talentos/consumibles/opciones de spec:
copia literalmente el bloque CharacterSuiteConfig{...} del _test.go oficial de
wowsims (mismo paquete Go, mismos identificadores), cambia el paquete a `main`
y sustituye las funciones de test por un main() que llama GetTest(0) y
serializa el resultado con protojson. Es el mismo patrón validado a mano para
el Cazador Supervivencia, generalizado por script en vez de repetido 21 veces.
"""

import pathlib
import re

WOWSIMS_SRC = pathlib.Path(__file__).resolve().parent / "wowsimcli-src"
SIM_DIR = WOWSIMS_SRC / "sim"

# (ruta del _test.go relativa a sim/, nombre de spec tal como aparece en ui/<spec>/)
SPEC_TEST_FILES = {
    "balance_druid": "druid/balance/balance_test.go",
    "feral_druid": "druid/feral/feral_test.go",
    "restoration_druid": "druid/restoration/restoration_test.go",
    "feral_tank_druid": "druid/tank/tank_test.go",
    "holy_paladin": "paladin/holy/holy_test.go",
    "protection_paladin": "paladin/protection/protection_test.go",
    "retribution_paladin": "paladin/retribution/retribution_test.go",
    "healing_priest": "priest/healing/healing_priest_test.go",
    "shadow_priest": "priest/shadow/shadow_priest_test.go",
    "smite_priest": "priest/smite/smite_priest_test.go",
    "elemental_shaman": "shaman/elemental/elemental_test.go",
    "enhancement_shaman": "shaman/enhancement/enhancement_test.go",
    "restoration_shaman": "shaman/restoration/restoration_test.go",
    "hunter": "hunter/hunter_test.go",
    "mage": "mage/mage_test.go",
    "rogue": "rogue/rogue_test.go",
    "warlock": "warlock/warlock_test.go",
    "warrior": "warrior/dps/dps_warrior_test.go",
    "protection_warrior": "warrior/protection/protection_warrior_test.go",
    "deathknight": "deathknight/dps/dps_deathknight_test.go",
    "tank_deathknight": "deathknight/tank/tank_deathknight_test.go",
}

CONFIG_BLOCK_RE = re.compile(
    r"core\.RunTestSuite\(t, t\.Name\(\), core\.FullCharacterTestSuiteGenerator\(core\.CharacterSuiteConfig\{(.*?)\}\)\)",
    re.DOTALL,
)
IMPORT_BLOCK_RE = re.compile(r"^import \(\n(.*?)\n\)\n", re.DOTALL | re.MULTILINE)
INIT_BLOCK_RE = re.compile(r"func init\(\) \{.*?\n\}\n", re.DOTALL)
PACKAGE_LINE_RE = re.compile(r"^package \w+\n")


def extract_first_config_block(test_source: str) -> str:
    match = CONFIG_BLOCK_RE.search(test_source)
    if not match:
        raise ValueError("No se encontró ningún bloque CharacterSuiteConfig")
    return match.group(1)


PACKAGE_NAME_RE = re.compile(r"^package (\w+)\n")


def generate_main_go(spec: str, test_source: str, rel_ui_prefix: str) -> str:
    config_block = extract_first_config_block(test_source)
    package_match = PACKAGE_NAME_RE.search(test_source)
    package_name = package_match.group(1) if package_match else "main"

    import_match = IMPORT_BLOCK_RE.search(test_source)
    imports = import_match.group(1) if import_match else ""

    # Se genera como fichero _test.go del MISMO paquete (no un binario `main`
    # aparte): así los identificadores del preset (talentos, consumibles,
    # opciones de spec) se resuelven directamente, sin reimportar el paquete
    # ni reconstruir sus valores a mano. No repite el init()/Register* del
    # _test.go original: ya se registra una vez al compilar el paquete junto
    # con ese fichero, y repetirlo haría fallar el registro por duplicado.
    return f'''package {package_name}

import (
{imports}
\t"fmt"
\t"os"

\t"google.golang.org/protobuf/encoding/protojson"
)

func TestGenExtractor(t *testing.T) {{
\tgenerator := core.FullCharacterTestSuiteGenerator(core.CharacterSuiteConfig{{{config_block}}})
\t// El último test de la suite generada es siempre "Average": el RaidSimRequest
\t// base (gearset+talentos+rotación del preset, sin variaciones) con opciones de
\t// simulación completas (más iteraciones), justo lo que se necesita como sim base.
\t_, _, _, rsr := generator.GetTest(generator.NumTests() - 1)

\tdata, err := protojson.MarshalOptions{{EmitUnpopulated: true, Indent: "  "}}.Marshal(rsr)
\tif err != nil {{
\t\tfmt.Fprintln(os.Stderr, "error marshaling:", err)
\t\tos.Exit(1)
\t}}
\tif err := os.WriteFile("input.json", data, 0644); err != nil {{
\t\tfmt.Fprintln(os.Stderr, "error writing file:", err)
\t\tos.Exit(1)
\t}}
\tfmt.Println("input.json generado ({spec})")
}}
'''


def main() -> None:
    generated = 0
    for spec, rel_path in SPEC_TEST_FILES.items():
        test_path = SIM_DIR / rel_path
        if not test_path.exists():
            print(f"[{spec}] AVISO: no existe {test_path}, se omite")
            continue

        test_source = test_path.read_text(encoding="utf-8")
        try:
            main_go = generate_main_go(spec, test_source, spec)
        except ValueError as exc:
            print(f"[{spec}] ERROR: {exc}")
            continue

        out_path = test_path.parent / "zzz_gen_extractor_test.go"
        out_path.write_text(main_go, encoding="utf-8")
        print(f"[{spec}] generado en {out_path}")
        generated += 1

    print(f"\nTotal generadores creados: {generated}/{len(SPEC_TEST_FILES)}")


if __name__ == "__main__":
    main()
