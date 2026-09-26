"""Empareja cada gearset (Tools/builds/<spec>.json) con su set de talentos y
rotación (APL) correspondiente, produciendo Tools/builds/_mapeo/<spec>.json.

Los presets.ts de wowsims no siguen una única convención de nombres, así que el
emparejamiento se intenta en este orden:

1. Sub-spec explícita en el nombre del gearset (ej. 'p1_mm' -> busca un talento/
   apl cuyo nombre contenga 'mm'/'marksman'/'MM').
2. Talento único por fase de contenido, sin sub-spec (ej. balance_druid: 'p1' ->
   'Phase1Talents').
3. Un solo set de talentos/apl para toda la spec (se usa para todas las fases).

Cualquier gearset que no encaje con confianza en ninguna de estas reglas se marca
"REVISAR" en el fichero de salida, con las opciones candidatas listadas, en vez de
adivinar. No se debe usar en simular_builds.py ninguna entrada marcada REVISAR sin
que un humano la resuelva primero.
"""

import json
import pathlib
import re

BUILDS_DIR = pathlib.Path(__file__).resolve().parent / "builds"
OUT_DIR = BUILDS_DIR / "_mapeo"

PHASE_RE = re.compile(r"^(preraid|p\d+)(?:_(.+))?$")

# Abreviaturas de sub-spec usadas en nombres de fichero -> palabras que aparecen
# en los nombres de talentos/APL para esa misma sub-spec. Necesario porque wowsims
# no sigue una convención 1:1 entre el sufijo de fichero y el nombre del preset
# (ej. "mm" en un fichero corresponde a "Marksman" en el código).
SUBSPEC_ALIASES = {
    "mm": ["marksman"],
    "sv": ["survival"],
    "bm": ["beastmastery", "beastmast"],
    "disc": ["disc"],
    "holy": ["holy"],
    "arms": ["arms"],
    "fury": ["fury"],
    "blood": ["blood"],
    "frost": ["frost"],
    "uh": ["unholy"],
    "2h": ["2h"],
    "dw": ["dualwield", "dw"],
    "ft": ["fireandtotem", "ft", "fire"],
    "wf": ["windfury", "wf"],
    "arcane": ["arcane"],
    "fire": ["fire"],
    "ffb": ["frostfire", "ffb"],
    "affliction": ["affliction"],
    "demodestro": ["demonology", "destruction"],
    "demo": ["demonology"],
    "destro": ["destruction"],
    "assassination": ["assassination"],
    "combat": ["combat"],
    "hemosub": ["hemo", "subtlety"],
    "dancesub": ["subtlety", "dance"],
    "balanced": ["standard"],
    "survival": ["ua", "standard"],
}


def normalize(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.lower())


# Sufijos que marcan una variante del preset base (rotación avanzada, AoE, etc.),
# no una sub-spec distinta. Se descartan al buscar el preset "base" de una subspec.
VARIANT_SUFFIXES = ["advanced", "aoe", "expose", "cleave", "sunder", "snd", "pesti"]


def filter_by_talent_tree(candidates: list, talent_tree: int):
    """Cuando se conoce el árbol de talentos dominante de la build, se descartan
    los presets de rotación/gear declarados para otro árbol distinto (campo
    talent_trees de PresetUtils.make*): reduce ambigüedad sin depender de
    coincidencias de nombre."""
    with_tree = [c for c in candidates if c.get("talent_trees")]
    if not with_tree:
        return candidates
    matching = [c for c in with_tree if talent_tree in c["talent_trees"]]
    return matching if matching else candidates


def find_by_subspec(candidates: list, subspec_tokens: list, key: str):
    subspec_join = "".join(subspec_tokens)

    # 1) Coincidencia exacta con el token COMPUESTO completo (ej. "uh_2h" ->
    #    "Unholy2HTalents"): la señal más específica, se intenta primero para
    #    no perder precisión cuando el token completo sí desambigua.
    joined_words = ["".join(w) for w in _cartesian_aliases(subspec_tokens)]
    exact_joined = [
        c for c in candidates
        if normalize(c[key]).replace("talents", "").rstrip("0123456789") in joined_words
    ]
    if len(exact_joined) >= 1:
        return exact_joined

    # 2) Coincidencia exacta con un solo token (ej. "frost" -> "FrostTalents").
    exact = [
        c for c in candidates
        if normalize(c[key]).replace("talents", "").rstrip("0123456789") == subspec_join
        or normalize(c[key]) == subspec_join
    ]
    if len(exact) == 1:
        return exact

    matches = []
    for token in subspec_tokens:
        words = SUBSPEC_ALIASES.get(token, []) + [token]
        for word in words:
            found = [c for c in candidates if word in normalize(c[key])]
            matches.extend(c for c in found if c not in matches)

    if len(matches) > 1:
        base_matches = [
            m for m in matches
            if not any(suffix in normalize(m[key]) for suffix in VARIANT_SUFFIXES)
        ]
        if len(base_matches) == 1:
            return base_matches
    return matches


def _cartesian_aliases(tokens):
    if not tokens:
        return [[]]
    head, *rest = tokens
    head_words = SUBSPEC_ALIASES.get(head, []) + [head]
    tail_combos = _cartesian_aliases(rest)
    return [[w] + combo for w in head_words for combo in tail_combos]


def phase_number(phase: str):
    return 0 if phase == "preraid" else int(phase[1:])


def find_by_phase(candidates: list, phase: str, key: str):
    phase_norm = phase.replace("p", "phase") if phase != "preraid" else "preraid"
    matches = [c for c in candidates if phase_norm in normalize(c[key])]
    if matches:
        return matches

    # Sin talento/apl propio de esta fase (frecuente en preraid o fases sin
    # cambios de talentos): usar el de la fase más próxima disponible.
    phase_candidates = []
    for c in candidates:
        m = re.search(r"phase(\d+)", normalize(c[key]))
        if m:
            phase_candidates.append((int(m.group(1)), c))
    if not phase_candidates:
        return []
    target = phase_number(phase)
    phase_candidates.sort(key=lambda pc: abs(pc[0] - target))
    best_phase = phase_candidates[0][0]
    return [c for p, c in phase_candidates if p == best_phase]


def dominant_talent_tree(talents_string: str):
    """Formato wowhead: bloques de dígitos separados por '-', un bloque por
    árbol de talentos (0, 1, 2). Devuelve el índice del árbol con más puntos."""
    trees = talents_string.split("-")
    points = [sum(int(d) for d in tree) for tree in trees]
    if not points or max(points) == 0:
        return None
    return points.index(max(points))


def pick_candidates(candidates_by_subspec, candidates_by_phase, all_candidates, key: str):
    """Devuelve (lista_de_nombres, regla). Si hay más de un candidato igual de
    válido, se devuelven TODOS: se prefiere cubrir cada variante real como una
    build de referencia distinta, en vez de forzar una única elección arbitraria."""
    if len(candidates_by_subspec) >= 1:
        return [c[key] for c in candidates_by_subspec], "subspec"
    if len(candidates_by_phase) >= 1:
        return [c[key] for c in candidates_by_phase], "fase"
    if len(all_candidates) >= 1:
        return [c[key] for c in all_candidates], "unico_o_toda_la_spec"
    return [], "sin_candidatos"


def build_mapping(spec_data: dict) -> dict:
    talent_sets = spec_data["talent_sets"]
    apl_presets = spec_data["apl_presets"]
    gear_presets = spec_data["gear_presets"]

    entries = []
    for gear in gear_presets:
        gear_file = gear["gear_file"] or ""
        match = PHASE_RE.match(gear_file)
        if not match:
            entries.append({
                "gear_file": gear_file,
                "label": gear["label"],
                "status": "REVISAR",
                "motivo": "nombre de fichero no sigue el patrón fase[_subspec]",
            })
            continue

        phase, subspec_raw = match.group(1), match.group(2)
        subspec_tokens = subspec_raw.split("_") if subspec_raw else []

        talent_by_subspec = find_by_subspec(talent_sets, subspec_tokens, "const_name") if subspec_tokens else []
        talent_by_phase = find_by_phase(talent_sets, phase, "const_name")
        talent_names, talent_rule = pick_candidates(talent_by_subspec, talent_by_phase, talent_sets, "const_name")

        # Si los talentos elegidos comparten un único árbol dominante, se usa
        # para descartar de entrada los APL/gear presets declarados para otro
        # árbol (campo talent_trees), antes de aplicar la heurística de nombre.
        chosen_talent_sets = [t for t in talent_sets if t["const_name"] in talent_names]
        dominant_trees = {dominant_talent_tree(t["talents_string"]) for t in chosen_talent_sets}
        dominant_trees.discard(None)
        apl_candidates = apl_presets
        if len(dominant_trees) == 1:
            apl_candidates = filter_by_talent_tree(apl_presets, next(iter(dominant_trees)))

        apl_by_subspec = find_by_subspec(apl_candidates, subspec_tokens, "const_name") if subspec_tokens else []
        apl_by_phase = find_by_phase(apl_candidates, phase, "const_name")
        apl_names, apl_rule = pick_candidates(apl_by_subspec, apl_by_phase, apl_candidates, "const_name")

        base = {
            "gear_file": gear_file,
            "label": gear["label"],
            "phase": phase,
            "subspec": subspec_raw,
            "faction": gear["faction"],
        }

        if not talent_names:
            entries.append({
                **base,
                "talent_set": None,
                "apl": None,
                "status": "REVISAR",
                "motivo": "sin ningún set de talentos candidato",
            })
            continue

        # Sin ningún APL candidato (sanadores sin APL en la spec, o una fase
        # temprana sin rotación propia): se usa rotación simple por defecto
        # del propio motor, no es un error.
        apl_options = apl_names if apl_names else [None]

        if len(talent_names) * len(apl_options) > 9:
            entries.append({
                **base,
                "talent_set": None,
                "apl": None,
                "status": "REVISAR",
                "motivo": (
                    f"demasiadas combinaciones talento×rotación "
                    f"({len(talent_names)}x{len(apl_options)}): {talent_names} / {apl_options}"
                ),
            })
            continue

        variant_needed = len(talent_names) > 1 or len(apl_options) > 1
        for talent_name in talent_names:
            for apl_name in apl_options:
                entry = {
                    **base,
                    "talent_set": talent_name,
                    "talent_rule": talent_rule,
                    "apl": apl_name,
                    "apl_rule": apl_rule if apl_presets else "sin_apl_en_spec",
                    "status": "ok",
                    "motivo": None,
                }
                if variant_needed:
                    entry["variante"] = True
                entries.append(entry)

    return {"spec": spec_data["spec"], "builds": entries}


def main() -> None:
    OUT_DIR.mkdir(exist_ok=True)

    total_ok = 0
    total_review = 0
    for spec_file in sorted(BUILDS_DIR.glob("*.json")):
        if spec_file.parent.name == "_mapeo":
            continue
        spec_data = json.loads(spec_file.read_text(encoding="utf-8"))
        mapping = build_mapping(spec_data)

        ok = sum(1 for b in mapping["builds"] if b["status"] == "ok")
        review = sum(1 for b in mapping["builds"] if b["status"] == "REVISAR")
        variantes = sum(1 for b in mapping["builds"] if b.get("variante"))
        total_ok += ok
        total_review += review

        out_path = OUT_DIR / spec_file.name
        out_path.write_text(json.dumps(mapping, indent=2, ensure_ascii=False), encoding="utf-8")
        marker = " <-- REVISAR" if review else ""
        extra = f" ({variantes} como variantes de un mismo gearset)" if variantes else ""
        print(f"[{mapping['spec']}] {ok} builds resultantes{extra}, {review} a revisar{marker}")

    print(f"\nTotal: {total_ok} builds de referencia generadas, {total_review} gearsets sin emparejar (revisar)")


if __name__ == "__main__":
    main()
