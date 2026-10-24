import type { AuditColumns } from './schema.ts';

/** The audit columns of a row `userId` creates now. */
export function createdBy(userId: string, now = Date.now()): Omit<AuditColumns, 'deleted_at'> {
  return { created_at: now, updated_at: now, created_by: userId, updated_by: userId };
}

/** The audit columns of a change `userId` makes now. */
export function updatedBy(userId: string, now = Date.now()): Pick<AuditColumns, 'updated_at' | 'updated_by'> {
  return { updated_at: now, updated_by: userId };
}
