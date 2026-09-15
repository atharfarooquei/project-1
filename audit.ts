/**
 * NABD :: audit log writer
 *
 * Append-only. Every entitlement decision worth explaining later, every
 * permit override, every payout approval. Audit writes never fail a request:
 * a lost log line is bad, a refused check-in because logging broke is worse.
 */

import type { SupabaseClient } from '@supabase/supabase-js';

export interface AuditEntry {
  actorId?: string | null;
  actorRole?: string | null;
  action: string;
  subjectType: string;
  subjectId?: string | null;
  beforeState?: Record<string, unknown> | null;
  afterState?: Record<string, unknown> | null;
  ipAddress?: string | null;
}

export async function logAudit(db: SupabaseClient, entry: AuditEntry): Promise<void> {
  try {
    await db.from('audit_log').insert({
      actor_id: entry.actorId ?? null,
      actor_role: entry.actorRole ?? null,
      action: entry.action,
      subject_type: entry.subjectType,
      subject_id: entry.subjectId ?? null,
      before_state: entry.beforeState ?? null,
      after_state: entry.afterState ?? null,
      ip_address: entry.ipAddress ?? null,
    });
  } catch (error) {
    console.error('[audit] write failed', entry.action, error);
  }
}
