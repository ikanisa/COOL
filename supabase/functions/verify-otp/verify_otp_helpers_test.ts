import { ensureAuthUser } from "./verify_otp_helpers.ts";

Deno.test(
  "ensureAuthUser falls back to admin list when auth lookup RPC is missing",
  async () => {
    let listUsersCalls = 0;
    let updateUserCalls = 0;
    let createUserCalls = 0;

    const adminClient = {
      rpc: async () => ({
        data: null,
        error: new Error(
          "Could not find the function public.find_auth_user_by_phone_or_email in the schema cache",
        ),
      }),
      auth: {
        admin: {
          listUsers: async () => {
            listUsersCalls += 1;
            return {
              data: {
                users: [
                  {
                    id: "auth-user-1",
                    email: "otp-250781234567@cool.app",
                    phone: "+250781234567",
                    created_at: "2026-04-11T12:00:00.000Z",
                    user_metadata: {
                      phone: "+250781234567",
                    },
                  },
                ],
              },
              error: null,
            };
          },
          updateUserById: async (_id: string, _payload: unknown) => {
            updateUserCalls += 1;
            return { data: {}, error: null };
          },
          createUser: async (_payload: unknown) => {
            createUserCalls += 1;
            return { data: {}, error: null };
          },
        },
      },
    };

    const result = await ensureAuthUser(
      adminClient as never,
      "+250781234567",
      "otp-250781234567@cool.app",
    );

    if (result.userId != "auth-user-1") {
      throw new Error(`Unexpected user id: ${result.userId}`);
    }
    if (result.created) {
      throw new Error("Expected the auth user to be updated, not created.");
    }
    if (listUsersCalls != 1) {
      throw new Error(`Expected one listUsers call, got ${listUsersCalls}`);
    }
    if (updateUserCalls != 1) {
      throw new Error(
        `Expected one updateUserById call, got ${updateUserCalls}`,
      );
    }
    if (createUserCalls != 0) {
      throw new Error(`Expected no createUser calls, got ${createUserCalls}`);
    }
  },
);
