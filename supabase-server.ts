/**
 * NABD :: server-side Supabase access
 *
 * Two clients, two purposes, never mixed up:
 *  - getUserFromRequest verifies the caller's JWT. It answers "who is this".
 *  - getServiceClient bypasses RLS. It answers "do the work".
 *
 * The service client must never be constructed on a path where the caller has
 * not first been identified, which is why the two live in one file and the
 * service key is read lazily.
 */

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { NextRequest } from 'next/server';

const url = process.env.SUPABASE_URL;
const anonKey = process.env.SUPABASE_ANON_KEY;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

export function getServiceClient(): SupabaseClient {
  if (!url || !serviceKey) {
    throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set.');
  }
  return createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    db: { schema: 'app' },
  });
}

export interface AuthedUser {
  id: string;
  email: string | null;
  role: string | null;
}

export async function getUserFromRequest(request: NextRequest): Promise<AuthedUser | null> {
  const header = request.headers.get('authorization');
  if (!header?.startsWith('Bearer ')) return null;
  if (!url || !anonKey) return null;

  const token = header.slice('Bearer '.length);
  const client = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) return null;

  return {
    id: data.user.id,
    email: data.user.email ?? null,
    role: (data.user.app_metadata?.role as string) ?? null,
  };
}

export async function requirePlatformAdmin(request: NextRequest): Promise<AuthedUser | null> {
  const user = await getUserFromRequest(request);
  return user?.role === 'platform_admin' ? user : null;
}

/** True when the caller is staff at the given venue. */
export async function staffsVenue(
  db: SupabaseClient,
  userId: string,
  venueId: string,
): Promise<boolean> {
  const { data } = await db
    .from('venue_staff')
    .select('id')
    .eq('user_id', userId)
    .eq('venue_id', venueId)
    .maybeSingle();
  return Boolean(data);
}
