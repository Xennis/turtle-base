/**
 * Key of the collection a relation field points to, in its `fields.config` -
 * the only thing it stores (cardinality isn't picked in the field editor).
 */
export const relationTargetCollectionIdKey = 'targetCollectionId';

export function encodeRelationConfig(targetCollectionId: string): string {
  return JSON.stringify({ [relationTargetCollectionIdKey]: targetCollectionId });
}

export function decodeRelationTargetCollectionId(config: string | null): string | undefined {
  if (config === null) return undefined;
  const json: unknown = JSON.parse(config);
  if (typeof json !== 'object' || json === null) return undefined;
  const target: unknown = Reflect.get(json, relationTargetCollectionIdKey);
  return typeof target === 'string' ? target : undefined;
}

/** A relation property value is a JSON array of target page ids. */
export function decodeRelationValue(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter((item) => typeof item === 'string');
}
