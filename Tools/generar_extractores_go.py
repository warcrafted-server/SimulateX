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
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from extraer_ep_stats import extract_ep_config

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

GEARSET_FIELD_RE = re.compile(r"GearSet:\s*core\.GetGearSet\(([^,]+),\s*([^)]+)\)")
ROTATION_FIELD_RE = re.compile(r"Rotation:\s*core\.GetAplRotation\(([^,]+),\s*([^)]+)\)")
TALENTS_FIELD_RE = re.compile(r"Talents:\s*(\w+),")


def extract_first_config_block(test_source: str) -> str:
    match = CONFIG_BLOCK_RE.search(test_source)
    if not match:
        raise ValueError("No se encontró ningún bloque CharacterSuiteConfig")
    return match.group(1)


def parameterize_config_block(config_block: str) -> str:
    """Sustituye los literales de gear/rotación/talentos del preset por
    defecto por variables que se leen de argumentos de línea de comandos, para
    poder generar cada build de la matriz sin recompilar el binario por build."""
    config_block = GEARSET_FIELD_RE.sub(
        "GearSet: core.GetGearSet(gearDir, gearFile)", config_block, count=1
    )
    config_block = ROTATION_FIELD_RE.sub(
        "Rotation: core.GetAplRotation(aplDir, aplFile)", config_block, count=1
    )
    config_block = TALENTS_FIELD_RE.sub("Talents: talentsOverride,", config_block, count=1)
    return config_block


PACKAGE_NAME_RE = re.compile(r"^package (\w+)\n")


def generate_main_go(spec: str, test_source: str, rel_ui_prefix: str) -> str:
    config_block = parameterize_config_block(extract_first_config_block(test_source))
    package_match = PACKAGE_NAME_RE.search(test_source)
    package_name = package_match.group(1) if package_match else "main"

    import_match = IMPORT_BLOCK_RE.search(test_source)
    imports = import_match.group(1) if import_match else ""

    # Se genera como fichero _test.go del MISMO paquete (no un binario `main`
    # aparte): así los identificadores del preset (consumibles, opciones de
    # spec, glifos) se resuelven directamente, sin reimportar el paquete ni
    # reconstruir sus valores a mano. Gear/rotación/talentos SÍ se parametrizan
    # (parameterize_config_block) porque cambian por cada build de la matriz;
    # el resto del preset (raza, consumibles...) se mantiene fijo, tal como lo
    # define wowsims para esa spec. No repite el init()/Register* del _test.go
    # original: ya se registra una vez al compilar el paquete junto con ese
    # fichero, y repetirlo haría fallar el registro por duplicado.
    # Los parámetros de la build (gear/rotación/talentos) se leen de variables
    # de entorno, no de flags: el fichero se ejecuta con `go test -run`, y los
    # flags custom chocan con los propios flags de `go test`.
    return f'''package {package_name}

import (
{imports}
\t"fmt"
\t"os"
\t"strconv"

\t"google.golang.org/protobuf/encoding/protojson"
)

func envOr(key, fallback string) string {{
\tif v := os.Getenv(key); v != "" {{
\t\treturn v
\t}}
\treturn fallback
}}

func TestGenExtractor(t *testing.T) {{
\tgearDir := os.Getenv("SIMX_GEAR_DIR")
\tgearFile := os.Getenv("SIMX_GEAR_FILE")
\taplDir := os.Getenv("SIMX_APL_DIR")
\taplFile := os.Getenv("SIMX_APL_FILE")
\t_, _ = aplDir, aplFile // no usadas si la spec no tiene Rotation vía GetAplRotation (ver ROTATION_FIELD_RE)
\ttalentsOverride := os.Getenv("SIMX_TALENTS")
\toutFile := envOr("SIMX_OUT_FILE", "input.json")
\titerations, _ := strconv.Atoi(envOr("SIMX_ITERATIONS", "2000"))

\tconfig := core.CharacterSuiteConfig{{{config_block}}}

\t// Construcción directa del RaidSimRequest "Average" (el mismo que produce
\t// FullCharacterTestSuiteGenerator como su último subtest), sin pasar por el
\t// generador de suite completo: éste evalúa también el subtest "AllItems"
\t// (cientos de objetos candidatos vía ItemFilter) al calcular NumTests(),
\t// coste innecesario y frágil solo para obtener el RaidSimRequest base.
\tdefaultPlayer := core.WithSpec(
\t\t&proto.Player{{
\t\t\tClass:         config.Class,
\t\t\tRace:          config.Race,
\t\t\tEquipment:     config.GearSet.GearSet,
\t\t\tConsumes:      config.Consumes,
\t\t\tBuffs:         core.FullIndividualBuffs,
\t\t\tTalentsString: config.Talents,
\t\t\tGlyphs:        config.Glyphs,
\t\t\tProfession1:   proto.Profession_Engineering,
\t\t\tRotation:      config.Rotation.Rotation,
\t\t\tCooldowns:     config.Cooldowns,

\t\t\tInFrontOfTarget:    config.InFrontOfTarget,
\t\t\tDistanceFromTarget: 30,
\t\t\tReactionTimeMs:      150,
\t\t\tChannelClipDelayMs:  50,
\t\t}},
\t\tconfig.SpecOptions.SpecOptions)

\tdefaultRaid := core.SinglePlayerRaidProto(defaultPlayer, core.FullPartyBuffs, core.FullRaidBuffs, core.FullDebuffs)
\tif config.IsTank {{
\t\tdefaultRaid.Tanks = append(defaultRaid.Tanks, &proto.UnitReference{{Type: proto.UnitReference_Player, Index: 0}})
\t}}
\tif config.IsHealer {{
\t\tdefaultRaid.TargetDummies = 1
\t}}

\trsr := &proto.RaidSimRequest{{
\t\tRaid:      defaultRaid,
\t\tEncounter: core.MakeSingleTargetEncounter(5),
\t\tSimOptions: &proto.SimOptions{{
\t\t\tIterations: int32(iterations),
\t\t\tIsTest:     true,
\t\t\tRandomSeed: 101,
\t\t}},
\t}}

\tdata, err := protojson.MarshalOptions{{EmitUnpopulated: true, Indent: "  "}}.Marshal(rsr)
\tif err != nil {{
\t\tfmt.Fprintln(os.Stderr, "error marshaling:", err)
\t\tos.Exit(1)
\t}}
\tif err := os.WriteFile(outFile, data, 0644); err != nil {{
\t\tfmt.Fprintln(os.Stderr, "error writing file:", err)
\t\tos.Exit(1)
\t}}
\tfmt.Println("input.json generado ({spec})")
}}
'''


def generate_stat_weights_go(spec: str, test_source: str, ep_config: dict) -> str:
    """Genera TestGenStatWeights: arma un StatWeightsRequest con el mismo
    jugador/buffs/encuentro que el extractor y llama a core.StatWeights(...),
    volcando el resultado (pesos brutos, no EP) a JSON. stats_to_weigh/
    pseudo_stats_to_weigh/ep_reference_stat vienen de ep_config (parseados de
    ui/<spec>/sim.ts por extraer_ep_stats.py, no transcritos a mano)."""
    config_block = parameterize_config_block(extract_first_config_block(test_source))
    package_match = PACKAGE_NAME_RE.search(test_source)
    package_name = package_match.group(1) if package_match else "main"

    import_match = IMPORT_BLOCK_RE.search(test_source)
    imports = import_match.group(1) if import_match else ""

    stats_list = ", ".join(f"proto.Stat_{s}" for s in ep_config["stats_to_weigh"])
    pseudo_stats_list = ", ".join(f"proto.PseudoStat_{s}" for s in ep_config["pseudo_stats_to_weigh"])
    ep_reference_stat = f"proto.Stat_{ep_config['ep_reference_stat']}"

    # envOr ya está declarada en zzz_gen_extractor_test.go, generado por
    # generate_main_go() en el mismo paquete: redeclararla aquí duplicaría el
    # símbolo y rompería la compilación.
    return f'''package {package_name}

import (
{imports}
\t"fmt"
\t"os"
\t"strconv"

\t"google.golang.org/protobuf/encoding/protojson"
)

func TestGenStatWeights(t *testing.T) {{
\tgearDir := os.Getenv("SIMX_GEAR_DIR")
\tgearFile := os.Getenv("SIMX_GEAR_FILE")
\taplDir := os.Getenv("SIMX_APL_DIR")
\taplFile := os.Getenv("SIMX_APL_FILE")
\t_, _ = aplDir, aplFile
\ttalentsOverride := os.Getenv("SIMX_TALENTS")
\toutFile := envOr("SIMX_SW_OUT_FILE", "stat_weights.json")
\titerations, _ := strconv.Atoi(envOr("SIMX_SW_ITERATIONS", "5000"))

\tconfig := core.CharacterSuiteConfig{{{config_block}}}

\tplayer := core.WithSpec(
\t\t&proto.Player{{
\t\t\tClass:         config.Class,
\t\t\tRace:          config.Race,
\t\t\tEquipment:     config.GearSet.GearSet,
\t\t\tConsumes:      config.Consumes,
\t\t\tBuffs:         core.FullIndividualBuffs,
\t\t\tTalentsString: config.Talents,
\t\t\tGlyphs:        config.Glyphs,
\t\t\tProfession1:   proto.Profession_Engineering,
\t\t\tRotation:      config.Rotation.Rotation,
\t\t\tCooldowns:     config.Cooldowns,

\t\t\tInFrontOfTarget:    config.InFrontOfTarget,
\t\t\tDistanceFromTarget: 30,
\t\t\tReactionTimeMs:      150,
\t\t\tChannelClipDelayMs:  50,
\t\t}},
\t\tconfig.SpecOptions.SpecOptions)

\tswr := &proto.StatWeightsRequest{{
\t\tPlayer:    player,
\t\tRaidBuffs: core.FullRaidBuffs,
\t\tPartyBuffs: core.FullPartyBuffs,
\t\tDebuffs:   core.FullDebuffs,
\t\tEncounter: core.MakeSingleTargetEncounter(5),
\t\tSimOptions: &proto.SimOptions{{
\t\t\tIterations: int32(iterations),
\t\t\tIsTest:     true,
\t\t\tRandomSeed: 101,
\t\t}},
\t\tStatsToWeigh:       []proto.Stat{{{stats_list}}},
\t\tPseudoStatsToWeigh: []proto.PseudoStat{{{pseudo_stats_list}}},
\t\tEpReferenceStat:    {ep_reference_stat},
\t}}
\tif config.IsTank {{
\t\tswr.Tanks = append(swr.Tanks, &proto.UnitReference{{Type: proto.UnitReference_Player, Index: 0}})
\t}}

\tresult := core.StatWeights(swr)
\tdata, err := protojson.MarshalOptions{{EmitUnpopulated: true, Indent: "  "}}.Marshal(result)
\tif err != nil {{
\t\tfmt.Fprintln(os.Stderr, "error marshaling:", err)
\t\tos.Exit(1)
\t}}
\tif err := os.WriteFile(outFile, data, 0644); err != nil {{
\t\tfmt.Fprintln(os.Stderr, "error writing file:", err)
\t\tos.Exit(1)
\t}}
\tfmt.Println("stat_weights.json generado ({spec})")
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

        try:
            ep_config = extract_ep_config(spec)
        except (FileNotFoundError, ValueError) as exc:
            print(f"[{spec}] AVISO: sin epStats/epWeights ({exc}), no se genera TestGenStatWeights")
            continue

        if ep_config["kind"] != "sim":
            print(f"[{spec}] usa epWeights preset (decisión 3), no se genera TestGenStatWeights")
            continue

        sw_go = generate_stat_weights_go(spec, test_source, ep_config)
        sw_out_path = test_path.parent / "zzz_gen_stat_weights_test.go"
        sw_out_path.write_text(sw_go, encoding="utf-8")
        print(f"[{spec}] pesos: generado en {sw_out_path}")

    print(f"\nTotal generadores creados: {generated}/{len(SPEC_TEST_FILES)}")


if __name__ == "__main__":
    main()
