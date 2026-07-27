import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const url = Deno.env.get('SUPABASE_URL');
    const publishableKey = Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ??
      Deno.env.get('SUPABASE_ANON_KEY');
    const serverKey = Deno.env.get('SUPABASE_SECRET_KEY') ??
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const authorization = request.headers.get('Authorization');
    if (!url || !publishableKey || !serverKey || !authorization) {
      return response(401, { error: 'Authentication required.' });
    }

    const userClient = createClient(url, publishableKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) {
      return response(401, { error: 'Authentication required.' });
    }

    const body = await request.json();
    const email = String(body.email ?? '').trim().toLowerCase();
    const bookId = String(body.book_id ?? '');
    const householdMemberId = body.household_member_id ?? null;
    const role = body.role === 'owner' ? 'owner' : 'member';
    const { data: invitation, error: invitationError } = await userClient.rpc(
      'create_book_invitation',
      {
        p_book_id: bookId,
        p_email: email,
        p_household_member_id: householdMemberId,
        p_role: role,
      },
    );
    if (invitationError) {
      return response(403, { error: 'Owner permission is required.' });
    }

    const adminClient = createClient(url, serverKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const redirectTo = Deno.env.get('PILGRIM_AUTH_REDIRECT_URL');
    const { error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(
      email,
      redirectTo ? { redirectTo } : undefined,
    );
    // Existing registered users discover the pending database invitation after
    // sign-in; an "already registered" email error does not invalidate it.
    const emailDelivery = inviteError ? 'pending_discovery' : 'sent';
    return response(200, { ...invitation, email_delivery: emailDelivery });
  } catch (_) {
    return response(400, { error: 'Could not create invitation.' });
  }
});

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
