//import SwiftUI
//import AuthenticationServices
//import CryptoKit
//
//struct AppleSignInView: View {
//    @State private var currentNonce: String?
//
//    var body: some View {
//        VStack {
//            Text("Welcome to Journey!")
//                .font(.largeTitle)
//                .padding(.bottom, 20)
//            HStack {
//                Spacer()
//                SignInWithAppleButton(.signIn, onRequest: configure, onCompletion: handle)
//                    .signInWithAppleButtonStyle(.black)
//                    .frame(width: 200, height: 36)
//                Spacer()
//            }
//        }
//    }
//
//    private func configure(_ request: ASAuthorizationAppleIDRequest) {
//        // Request what you need. Name/email only come the FIRST time.
//        request.requestedScopes = [.fullName, .email]
//
//        // Add a nonce to defend against replay attacks (your backend will verify it).
//        let nonce = randomNonce()
//        currentNonce = nonce
//        request.nonce = sha256(nonce)
//    }
//
//    private func handle(_ result: Result<ASAuthorization, Error>) {
//        switch result {
//        case .failure(let error):
//            print("Apple Sign In failed:", error)
//
//        case .success(let auth):
//            guard
//                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
//                let identityToken = credential.identityToken,
//                let tokenString = String(data: identityToken, encoding: .utf8),
//                let nonce = currentNonce
//            else { return }
//
//            // Useful fields:
//            let appleUserID = credential.user        // stable per app+team
//            let email = credential.email             // only on first sign-in (or if user disclosed)
//            let fullName = credential.fullName       // only on first sign-in
//
//            // Send to your backend to verify & exchange for your tokens
//            Task {
//                do {
//                    try await AuthAPI.shared.appleSignIn(
//                        idToken: tokenString,
//                        rawNonce: nonce,
//                        appleUserID: appleUserID,
//                        email: email,
//                        fullName: fullName
//                    )
//                    // Backend returns your access/refresh tokens + your internal user id
//                } catch {
//                    print("Backend exchange failed:", error)
//                }
//            }
//        }
//    }
//}
//
//// MARK: - Nonce helpers
//private func randomNonce(length: Int = 32) -> String {
//    precondition(length > 0)
//    let charset: [Character] =
//        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
//    var result = ""
//    var remaining = length
//
//    while remaining > 0 {
//        var randoms = [UInt8](repeating: 0, count: 16)
//        let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
//        if status != errSecSuccess { fatalError("Unable to generate nonce.") }
//        randoms.forEach { random in
//            if remaining == 0 { return }
//            if random < charset.count {
//                result.append(charset[Int(random)])
//                remaining -= 1
//            }
//        }
//    }
//    return result
//}
//
//private func sha256(_ input: String) -> String {
//    let hashed = SHA256.hash(data: Data(input.utf8))
//    return hashed.compactMap { String(format: "%02x", $0) }.joined()
//}
