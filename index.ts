import { createClient } from 'npm:@supabase/supabase-js@2'
import { GoogleAuth } from 'npm:google-auth-library@9'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: cors })
  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return new Response('Unauthorized', { status: 401, headers: cors })
    const url = Deno.env.get('SUPABASE_URL')!
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const userClient = createClient(url, anon, { global: { headers: { Authorization: authHeader } } })
    const { data: { user }, error: authError } = await userClient.auth.getUser()
    if (authError || !user) return new Response('Unauthorized', { status: 401, headers: cors })

    const { conversation_id, message_id } = await req.json()
    if (typeof conversation_id !== 'string' || typeof message_id !== 'string') {
      return new Response('Invalid request', { status: 400, headers: cors })
    }
    const { data: membership } = await userClient.from('conversation_members')
      .select('conversation_id').eq('conversation_id', conversation_id).eq('user_id', user.id).maybeSingle()
    if (!membership) return new Response('Forbidden', { status: 403, headers: cors })

    const admin = createClient(url, serviceKey)
    const { data: message, error: messageError } = await admin.from('messages')
      .select('id,conversation_id,sender_id,body,message_type').eq('id', message_id)
      .eq('conversation_id', conversation_id).single()
    if (messageError || !message || message.sender_id !== user.id) {
      return new Response('Message not found', { status: 404, headers: cors })
    }
    const { data: members } = await admin.from('conversation_members')
      .select('user_id').eq('conversation_id', conversation_id).neq('user_id', user.id)
    const recipientIds = (members ?? []).map((m) => m.user_id)
    if (!recipientIds.length) return new Response(JSON.stringify({ sent: 0 }), { headers: { ...cors, 'Content-Type': 'application/json' } })
    const { data: tokens } = await admin.from('device_tokens').select('push_token,user_id').in('user_id', recipientIds)
    if (!tokens?.length) return new Response(JSON.stringify({ sent: 0 }), { headers: { ...cors, 'Content-Type': 'application/json' } })

    const serviceAccountRaw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
    if (!serviceAccountRaw) return new Response('FIREBASE_SERVICE_ACCOUNT secret missing', { status: 500, headers: cors })
    const serviceAccount = JSON.parse(serviceAccountRaw)
    const googleAuth = new GoogleAuth({ credentials: serviceAccount, scopes: ['https://www.googleapis.com/auth/firebase.messaging'] })
    const client = await googleAuth.getClient()
    const accessToken = await client.getAccessToken()
    const title = message.message_type === 'text' ? 'New message' : `New ${message.message_type}`
    const body = message.message_type === 'text' ? String(message.body).slice(0, 120) : 'You received an attachment'
    let sent = 0
    for (const item of tokens) {
      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${accessToken.token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: { token: item.push_token, notification: { title, body }, data: { conversation_id, message_id } } }),
      })
      if (response.ok) sent++
      else if (response.status === 404 || response.status === 400) {
        await admin.from('device_tokens').delete().eq('push_token', item.push_token)
      }
    }
    return new Response(JSON.stringify({ sent }), { headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error) }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
  }
})
