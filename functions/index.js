const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.createSupabaseToken = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated.",
    );
  }
  const uid = context.auth.uid;
  try {
    const customToken = await admin.auth().createCustomToken(uid);
    return {token: customToken};
  } catch (error) {
    throw new functions.https.HttpsError(
        "internal",
        `Error generating token: ${error.message}`,
    );
  }
});
