import type { FieldVariant } from '@turtle-base/plugin-api';

import type { AppDatabase } from '../../../core/database/app-database.ts';
import { createdBy, updatedBy } from '../../../core/database/audit.ts';
import type { Field } from '../../../core/database/schema.ts';
import { decodePageProperties, PagesRepository } from '../../pages/data/pages-repository.ts';
import type { AnyFieldType, Json } from './base-field-type.ts';
import { conversionMode, type TypeChangePlan } from './field-conversion.ts';
import { FieldTypeRegistry, type FieldTypeChoice } from './field-type-registry.ts';
import { decodeFieldConfig, fieldVariantKey, ResolvedField } from './resolved-field.ts';
import {
  decodeSelectOptions,
  decodeSelectOptionsJson,
  encodeSelectConfig,
  nextOptionColor,
  type SelectOption,
} from './select-field.ts';

type Changes = Partial<Pick<Field, 'name' | 'type' | 'config' | 'position' | 'deleted_at'>>;

export class FieldsRepository {
  readonly #database: AppDatabase;

  /** Resolves the field's old and new type when planning a type change. */
  readonly #fieldTypes: FieldTypeRegistry;

  constructor(database: AppDatabase, fieldTypes = new FieldTypeRegistry()) {
    this.#database = database;
    this.#fieldTypes = fieldTypes;
  }

  /** Active (non-deleted) fields of a collection, in column order. */
  listActiveInCollection(collectionId: string): Promise<Field[]> {
    return this.#database.db
      .selectFrom('fields')
      .selectAll()
      .where('collection_id', '=', collectionId)
      .where('deleted_at', 'is', null)
      .orderBy('position')
      .orderBy('id')
      .execute();
  }

  byId(id: string): Promise<Field> {
    return this.#database.db.selectFrom('fields').selectAll().where('id', '=', id).executeTakeFirstOrThrow();
  }

  /**
   * `config` is the base type's own config (e.g. encodeSelectConfig);
   * `variant` and its preset are merged into it. `id` defaults to a fresh
   * uuid - plugins derive theirs (see PluginInstancesRepository).
   */
  async create(options: {
    collectionId: string;
    name: string;
    type: AnyFieldType;
    variant?: FieldVariant;
    config?: string | null;
    id?: string;
  }): Promise<string> {
    const id = options.id ?? crypto.randomUUID();
    const userId = await this.#database.currentUserId();
    await this.#database.db
      .insertInto('fields')
      .values({
        id,
        collection_id: options.collectionId,
        name: options.name,
        type: options.type.id,
        position: await this.#nextPosition(options.collectionId),
        config: encodeConfig(withVariant(decodeFieldConfig(options.config ?? null), options.variant)),
        deleted_at: null,
        ...createdBy(userId),
      })
      .execute();
    return id;
  }

  rename(id: string, name: string): Promise<void> {
    return this.#update(id, { name });
  }

  /** Changes the type right away - see {@link planTypeChange} to preview the effect on the values first. */
  async changeType(id: string, choice: FieldTypeChoice): Promise<void> {
    await this.applyTypeChange(await this.planTypeChange(id, choice));
  }

  /**
   * What changing the field's type to `choice` does to its values (see
   * FIELD_TYPES.md), without writing anything. The config is kept, so e.g.
   * select options survive a switch to multi-select and back; a switch to
   * (multi-)select adds an option per distinct value.
   */
  async planTypeChange(id: string, choice: FieldTypeChoice): Promise<TypeChangePlan> {
    const row = await this.byId(id);
    const from = this.#fieldTypes.resolve(row);
    const to = choice.base;
    const mode = conversionMode(from.base, to);
    const json = withVariant(decodeFieldConfig(row.config), choice.variant);
    const entries = await this.#database.db
      .selectFrom('pages')
      .select(['id', 'properties'])
      .where('collection_id', '=', row.collection_id)
      .where('deleted_at', 'is', null)
      .execute();
    const raws = new Map<string, unknown>();
    for (const entry of entries) {
      const raw = decodePageProperties(entry.properties)[id];
      if (!ResolvedField.isEmptyRaw(raw)) raws.set(entry.id, raw);
    }

    const fromSelect = from.base.kind === 'select' || from.base.kind === 'multiSelect';
    if ((to.kind === 'select' || to.kind === 'multiSelect') && !fromSelect && mode === 'lazy') {
      const options: SelectOption[] = decodeSelectOptionsJson(json);
      const names = new Set(options.map((option) => option.name.toLowerCase()));
      for (const raw of raws.values()) {
        const plain = from.plain(raw);
        for (const name of to.multiple ? plain.split(',') : [plain]) {
          const trimmed = name.trim();
          if (trimmed.length === 0 || names.has(trimmed.toLowerCase())) continue;
          names.add(trimmed.toLowerCase());
          options.push({ id: crypto.randomUUID(), name: trimmed, color: nextOptionColor(options) });
        }
      }
      json['options'] = options.map(({ id: optionId, name, color }) => ({ id: optionId, name, color }));
    }

    const config = encodeConfig(json);
    const target = this.#fieldTypes.resolve({ ...row, type: to.id, config });
    const titles =
      from.base.kind === 'relation' && mode === 'rewrite'
        ? await this.#titlesOf([...raws.values()].flatMap((raw) => relationIdsOf(from, raw)))
        : new Map<string, string>();

    const rewrites = new Map<string, Json>();
    const invalidSamples: string[] = [];
    let invalidCount = 0;
    if (mode !== 'none') {
      for (const [pageId, raw] of raws) {
        let converted: unknown = raw;
        if (mode === 'rewrite') {
          const plain =
            from.base.kind === 'relation' && from.valueOf(raw) !== undefined
              ? relationIdsOf(from, raw)
                  .map((pageIdOfTitle) => titles.get(pageIdOfTitle) ?? '?')
                  .join(', ')
              : from.plain(raw);
          // Kept as plain text when it doesn't parse, rather than as ids that mean nothing to the new type.
          const parsed = target.parse(plain);
          const rewritten = parsed.kind === 'value' ? parsed.stored : plain;
          rewrites.set(pageId, rewritten);
          converted = rewritten;
        }
        if (target.errorFor(converted) !== undefined) {
          invalidCount++;
          if (invalidSamples.length < 3) invalidSamples.push(from.display(raw));
        }
      }
    }

    return {
      fieldId: id,
      mode,
      type: to.id,
      config,
      valueCount: raws.size,
      invalidCount,
      invalidSamples,
      rewrites,
    };
  }

  /** Writes a plan from {@link planTypeChange}. A plan of mode `none` is ignored. */
  async applyTypeChange(plan: TypeChangePlan): Promise<void> {
    if (plan.mode === 'none') return;
    await this.#database.transaction(async (tx) => {
      await new FieldsRepository(tx, this.#fieldTypes).#update(plan.fieldId, { type: plan.type, config: plan.config });
      const pages = new PagesRepository(tx);
      for (const [pageId, value] of plan.rewrites) await pages.setPropertyValue(pageId, plan.fieldId, value);
    });
  }

  /** `config` is the base type's own config - the field's variant is kept. */
  async updateConfig(id: string, config: string | null): Promise<void> {
    const variantId = decodeFieldConfig((await this.byId(id)).config)[fieldVariantKey];
    const json: Record<string, unknown> = { ...decodeFieldConfig(config) };
    if (variantId !== undefined) json[fieldVariantKey] = variantId;
    await this.#update(id, { config: encodeConfig(json) });
  }

  /** Sets single config keys, keeping all others - a null value removes its key. */
  async updateConfigValues(id: string, values: Readonly<Record<string, unknown>>): Promise<void> {
    const merged = { ...decodeFieldConfig((await this.byId(id)).config), ...values };
    const json = Object.fromEntries(
      Object.entries(merged).filter(([, value]) => value !== null && value !== undefined),
    );
    await this.#update(id, { config: encodeConfig(json) });
  }

  /**
   * Appends a new option to a select/multi-select field, with the next
   * palette color. Like the other option methods, it reads the field's
   * current config fresh rather than trusting a caller's possibly stale copy.
   */
  async addSelectOption(fieldId: string, name: string): Promise<SelectOption> {
    const options = await this.#selectOptionsOf(fieldId);
    const option: SelectOption = { id: crypto.randomUUID(), name, color: nextOptionColor(options) };
    await this.updateConfig(fieldId, encodeSelectConfig([...options, option]));
    return option;
  }

  /** Renames and/or recolors an option, matched by its id. Values reference options by id, so no entry changes. */
  async updateSelectOption(fieldId: string, option: SelectOption): Promise<void> {
    const options = await this.#selectOptionsOf(fieldId);
    await this.updateConfig(fieldId, encodeSelectConfig(options.map((o) => (o.id === option.id ? option : o))));
  }

  /**
   * Entries still referencing the option keep its id - it's skipped when
   * reading (see resolveSelectValue) instead of rewriting every entry.
   */
  async removeSelectOption(fieldId: string, optionId: string): Promise<void> {
    const options = await this.#selectOptionsOf(fieldId);
    await this.updateConfig(fieldId, encodeSelectConfig(options.filter((o) => o.id !== optionId)));
  }

  reorder(id: string, position: number): Promise<void> {
    return this.#update(id, { position });
  }

  /** Gives the fields `orderedIds`' order, only touching the ones whose position changes. */
  async reorderAll(orderedIds: readonly string[]): Promise<void> {
    if (orderedIds.length === 0) return;
    const rows = await this.#database.db
      .selectFrom('fields')
      .select(['id', 'position'])
      .where('id', 'in', orderedIds)
      .execute();
    const positions = new Map(rows.map((row) => [row.id, row.position]));
    await this.#database.transaction(async (tx) => {
      const fields = new FieldsRepository(tx, this.#fieldTypes);
      for (const [index, id] of orderedIds.entries()) {
        if (positions.get(id) !== index) await fields.reorder(id, index);
      }
    });
  }

  softDelete(id: string): Promise<void> {
    return this.#update(id, { deleted_at: Date.now() });
  }

  restore(id: string): Promise<void> {
    return this.#update(id, { deleted_at: null });
  }

  async #selectOptionsOf(fieldId: string): Promise<SelectOption[]> {
    return decodeSelectOptions((await this.byId(fieldId)).config);
  }

  async #titlesOf(pageIds: readonly string[]): Promise<Map<string, string>> {
    const ids = [...new Set(pageIds)];
    if (ids.length === 0) return new Map();
    const pages = await this.#database.db.selectFrom('pages').select(['id', 'title']).where('id', 'in', ids).execute();
    return new Map(pages.map((page) => [page.id, page.title.length === 0 ? 'Untitled' : page.title]));
  }

  async #update(id: string, changes: Changes): Promise<void> {
    const userId = await this.#database.currentUserId();
    await this.#database.db
      .updateTable('fields')
      .set({ ...changes, ...updatedBy(userId) })
      .where('id', '=', id)
      .execute();
  }

  async #nextPosition(collectionId: string): Promise<number> {
    const { max } = await this.#database.db
      .selectFrom('fields')
      .select((eb) => eb.fn.max('position').as('max'))
      .where('collection_id', '=', collectionId)
      .executeTakeFirstOrThrow();
    return (max ?? -1) + 1;
  }
}

/** The config with `variant` set to the variant's id (plus its preset), or without one. */
function withVariant(
  config: Readonly<Record<string, unknown>>,
  variant: FieldVariant | undefined,
): Record<string, unknown> {
  const json: Record<string, unknown> = { ...config, ...variant?.configPreset };
  if (variant === undefined) delete json[fieldVariantKey];
  else json[fieldVariantKey] = variant.id;
  return json;
}

function encodeConfig(json: Readonly<Record<string, unknown>>): string | null {
  return Object.keys(json).length === 0 ? null : JSON.stringify(json);
}

function relationIdsOf(field: ResolvedField, raw: unknown): string[] {
  const value = field.valueOf(raw);
  return Array.isArray(value) ? value.filter((item) => typeof item === 'string') : [];
}
