import { serve } from "https://deno.land/std@0.192.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function normalizePhone(rawPhone: string): string {
  // إزالة المسافات والرموز والـ + والإبقاء على الأرقام فقط
  return rawPhone.replace(/\D/g, "");
}

function generateSixDigitOtp(): string {
  const num = crypto.getRandomValues(new Uint32Array(1))[0] % 900000;
  return String(100000 + num);
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const whatsappToken = Deno.env.get("WHATSAPP_ACCESS_TOKEN") ?? "";
    const phoneNumberId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID") ?? "";
    const templateName =
      Deno.env.get("WHATSAPP_OTP_TEMPLATE") ?? "otp_verification";
    const templateLang = Deno.env.get("WHATSAPP_OTP_LANG") ?? "ar";

    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(
        JSON.stringify({
          ok: false,
          error: "إعدادات Supabase غير مكتملة في بيئة الدالة",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const body = await req.json();

    const action = String(body?.action ?? "").trim();
    const cleanPhone = normalizePhone(
      String(body?.phone_number ?? body?.phone ?? ""),
    );

    if (!cleanPhone || cleanPhone.length < 8) {
      return new Response(
        JSON.stringify({
          ok: false,
          error: "يرجى إدخال رقم هاتف صحيح بالصيغة الدولية",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // =========================
    // الحالة الأولى: إرسال رمز OTP
    // =========================
    if (action === "send") {
      if (!whatsappToken || !phoneNumberId) {
        return new Response(
          JSON.stringify({
            ok: false,
            error:
              "متغيرات WHATSAPP_ACCESS_TOKEN أو WHATSAPP_PHONE_NUMBER_ID غير مضبوطة",
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const otpCode = generateSixDigitOtp();
      const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString();

      // إبطال الأكواد السابقة غير المستخدمة لنفس الرقم قبل حفظ الجديد
      await supabase
        .from("otp_codes")
        .update({ is_used: true })
        .eq("phone_number", cleanPhone)
        .eq("is_used", false);

      const { error: insertError } = await supabase.from("otp_codes").insert({
        phone_number: cleanPhone,
        otp_code: otpCode,
        expires_at: expiresAt,
        is_used: false,
      });

      if (insertError) {
        return new Response(
          JSON.stringify({
            ok: false,
            error: "تعذر حفظ رمز التحقق في قاعدة البيانات",
            details: insertError.message,
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const waResponse = await fetch(
        `https://graph.facebook.com/v21.0/${phoneNumberId}/messages`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${whatsappToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            messaging_product: "whatsapp",
            recipient_type: "individual",
            to: cleanPhone,
            type: "template",
            template: {
              name: templateName,
              language: { code: templateLang },
              components: [
                {
                  type: "body",
                  parameters: [{ type: "text", text: otpCode }],
                },
                {
                  type: "button",
                  sub_type: "url",
                  index: "0",
                  parameters: [{ type: "text", text: otpCode }],
                },
              ],
            },
          }),
        },
      );

      const waData = await waResponse.json();

      if (!waResponse.ok) {
        return new Response(
          JSON.stringify({
            ok: false,
            error: "فشل إرسال الرسالة عبر WhatsApp Cloud API",
            meta_error: waData,
          }),
          {
            status: 502,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      return new Response(
        JSON.stringify({
          ok: true,
          message: "تم إرسال رمز التحقق عبر واتساب بنجاح",
          expires_at: expiresAt,
          whatsapp_message_id: waData?.messages?.[0]?.id ?? null,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // =========================
    // الحالة الثانية: التحقق من OTP
    // =========================
    if (action === "verify") {
      const codeInput = String(body?.otp_code ?? body?.code ?? "").trim();

      if (!codeInput) {
        return new Response(
          JSON.stringify({ ok: false, error: "يرجى إدخال رمز التحقق" }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const { data: rows, error: selectError } = await supabase
        .from("otp_codes")
        .select("*")
        .eq("phone_number", cleanPhone)
        .eq("is_used", false)
        .order("created_at", { ascending: false })
        .limit(1);

      if (selectError || !rows || rows.length === 0) {
        return new Response(
          JSON.stringify({
            ok: false,
            error: "لا يوجد رمز تحقق نشط لهذا الرقم",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const latestOtp = rows[0];
      const isExpired = new Date(latestOtp.expires_at).getTime() < Date.now();

      if (isExpired) {
        await supabase
          .from("otp_codes")
          .update({ is_used: true })
          .eq("id", latestOtp.id);

        return new Response(
          JSON.stringify({
            ok: false,
            error: "انتهت صلاحية رمز التحقق، اطلب رمزاً جديداً",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      if (String(latestOtp.otp_code).trim() !== codeInput) {
        return new Response(
          JSON.stringify({ ok: false, error: "رمز التحقق غير صحيح" }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const { error: updateError } = await supabase
        .from("otp_codes")
        .update({ is_used: true })
        .eq("id", latestOtp.id);

      if (updateError) {
        return new Response(
          JSON.stringify({
            ok: false,
            error: "تعذر تحديث حالة استخدام الرمز",
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      return new Response(
        JSON.stringify({
          ok: true,
          verified: true,
          phone_number: cleanPhone,
          message: "تم التحقق من الرقم بنجاح",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(
      JSON.stringify({
        ok: false,
        error: "قيمة action غير مدعومة، استخدم send أو verify",
      }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: "حدث خطأ غير متوقع في الدالة",
        details: String(err),
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
