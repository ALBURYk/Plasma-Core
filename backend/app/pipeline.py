from __future__ import annotations

from dataclasses import dataclass


THREE_TO_ONE = {
    "ALA": "A",
    "ARG": "R",
    "ASN": "N",
    "ASP": "D",
    "CYS": "C",
    "GLN": "Q",
    "GLU": "E",
    "GLY": "G",
    "HIS": "H",
    "ILE": "I",
    "LEU": "L",
    "LYS": "K",
    "MET": "M",
    "PHE": "F",
    "PRO": "P",
    "SER": "S",
    "THR": "T",
    "TRP": "W",
    "TYR": "Y",
    "VAL": "V",
}

ONE_TO_THREE = {value: key for key, value in THREE_TO_ONE.items()}

DNA_CODONS = {
    "A": "GCT",
    "R": "CGT",
    "N": "AAC",
    "D": "GAC",
    "C": "TGC",
    "Q": "CAG",
    "E": "GAA",
    "G": "GGT",
    "H": "CAC",
    "I": "ATT",
    "L": "CTG",
    "K": "AAA",
    "M": "ATG",
    "F": "TTC",
    "P": "CCT",
    "S": "TCT",
    "T": "ACC",
    "W": "TGG",
    "Y": "TAC",
    "V": "GTT",
}


@dataclass(frozen=True)
class Residue:
    index: int
    chain: str
    pdb_number: str
    name: str


@dataclass(frozen=True)
class Mutation:
    position: int
    original: str
    replacement: str
    reason: str


def optimize_pdb(pdb_text: str, temperature: float, ph: float) -> dict[str, object]:
    residues = parse_residues(pdb_text)
    if not residues:
        raise ValueError("No amino acid residues were found in the PDB file.")

    sequence = "".join(THREE_TO_ONE.get(residue.name, "X") for residue in residues)
    mutations = choose_mutations(residues=residues, temperature=temperature, ph=ph)
    optimized_sequence = apply_mutations(sequence=sequence, mutations=mutations)
    optimized_pdb = rewrite_residue_names(pdb_text=pdb_text, residues=residues, mutations=mutations)
    dna = protein_to_dna(optimized_sequence)

    return {
        "optimized_pdb": optimized_pdb,
        "fasta": build_fasta(dna=dna, temperature=temperature, ph=ph, mutations=mutations),
        "amino_acid_sequence": optimized_sequence,
        "mutations": [
            {
                "position": mutation.position,
                "original": mutation.original,
                "replacement": mutation.replacement,
                "reason": mutation.reason,
            }
            for mutation in mutations
        ],
    }


def parse_residues(pdb_text: str) -> list[Residue]:
    residues: list[Residue] = []
    seen: set[tuple[str, str]] = set()

    for line in pdb_text.splitlines():
        if not line.startswith("ATOM") or len(line) < 26:
            continue

        name = line[17:20].strip().upper()
        if name not in THREE_TO_ONE:
            continue

        chain = line[21:22].strip() or "A"
        pdb_number = line[22:26].strip()
        key = (chain, pdb_number)
        if key in seen:
            continue

        seen.add(key)
        residues.append(
            Residue(
                index=len(residues) + 1,
                chain=chain,
                pdb_number=pdb_number,
                name=name,
            )
        )

    return residues


def choose_mutations(residues: list[Residue], temperature: float, ph: float) -> list[Mutation]:
    replacements = {
        "ASN": ("D", "asparagine deamidation risk at elevated temperature"),
        "GLN": ("E", "glutamine deamidation risk at elevated temperature"),
        "GLY": ("A", "glycine loop flexibility reduced for thermostability"),
        "MET": ("L", "methionine oxidation-prone side chain replaced"),
        "CYS": ("S", "free cysteine replaced to reduce unwanted crosslinking"),
    }
    ph_replacements = {
        "ASP": ("N", "acidic residue softened for alkaline pH target"),
        "GLU": ("Q", "acidic residue softened for alkaline pH target"),
    }

    mutations: list[Mutation] = []
    for residue in residues:
        if len(mutations) >= 6:
            break

        replacement: tuple[str, str] | None = None
        if temperature >= 42:
            replacement = replacements.get(residue.name)
        if ph >= 8.0:
            replacement = ph_replacements.get(residue.name) or replacement

        if replacement is None:
            continue

        one_letter = THREE_TO_ONE[residue.name]
        replacement_one, reason = replacement
        if replacement_one == one_letter:
            continue

        mutations.append(
            Mutation(
                position=residue.index,
                original=one_letter,
                replacement=replacement_one,
                reason=reason,
            )
        )

    return mutations


def apply_mutations(sequence: str, mutations: list[Mutation]) -> str:
    sequence_items = list(sequence)
    for mutation in mutations:
        sequence_items[mutation.position - 1] = mutation.replacement
    return "".join(sequence_items)


def rewrite_residue_names(pdb_text: str, residues: list[Residue], mutations: list[Mutation]) -> str:
    mutation_by_position = {mutation.position: mutation for mutation in mutations}
    residue_by_key = {
        (residue.chain, residue.pdb_number): residue
        for residue in residues
        if residue.index in mutation_by_position
    }

    rewritten: list[str] = []
    for line in pdb_text.splitlines():
        if line.startswith("ATOM") and len(line) >= 26:
            chain = line[21:22].strip() or "A"
            pdb_number = line[22:26].strip()
            residue = residue_by_key.get((chain, pdb_number))
            if residue is not None:
                mutation = mutation_by_position[residue.index]
                replacement_name = ONE_TO_THREE[mutation.replacement]
                line = f"{line[:17]}{replacement_name:>3}{line[20:]}"
        rewritten.append(line)

    return "\n".join(rewritten) + "\n"


def protein_to_dna(sequence: str) -> str:
    return "".join(DNA_CODONS.get(amino_acid, "NNN") for amino_acid in sequence) + "TAA"


def build_fasta(dna: str, temperature: float, ph: float, mutations: list[Mutation]) -> str:
    mutation_label = ",".join(
        f"{mutation.original}{mutation.position}{mutation.replacement}"
        for mutation in mutations
    ) or "none"
    header = (
        ">plasma_core_petase_5xjh_optimized "
        f"temperature={temperature:.1f}C ph={ph:.1f} mutations={mutation_label}"
    )
    return f"{header}\n{wrap_sequence(dna)}\n"


def wrap_sequence(sequence: str, width: int = 72) -> str:
    return "\n".join(sequence[index : index + width] for index in range(0, len(sequence), width))
