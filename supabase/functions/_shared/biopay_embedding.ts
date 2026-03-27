export const BIOPAY_EMBEDDING_LENGTH = 192;

export function normalizeBiopayEmbedding(input: unknown): number[] {
  if (!Array.isArray(input) || input.length !== BIOPAY_EMBEDDING_LENGTH) {
    throw new Error(
      `BioPay embedding must contain exactly ${BIOPAY_EMBEDDING_LENGTH} values.`,
    );
  }

  return input.map((value) => {
    const numberValue = typeof value === "number" ? value : Number(value);
    if (!Number.isFinite(numberValue)) {
      throw new Error("BioPay embedding contains a non-numeric value.");
    }
    return numberValue;
  });
}
