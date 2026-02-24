import SwiftUI

// MARK: - AuthLandingView
// The entry point for unauthenticated users. Shows the app hero,
// the login form, and a link to the registration flow.

struct AuthLandingView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        NavigationStack {
            ZStack {
                JourneyBackground()
                ScrollView {
                    VStack(spacing: DS.Spacing.xl) {
                        heroSection
                        LoginView()
                        registerLink
                        Spacer(minLength: DS.Spacing.xl)
                    }
                }
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: DS.Spacing.md) {
            JourneyAvatar(size: 84)
                .shadow(color: DS.Shadow.color, radius: DS.Shadow.radius, y: DS.Shadow.y)
                .padding(.top, DS.Spacing.xxl)

            Text("Journey")
                .font(DS.fontSize(30, weight: .semibold))
                .foregroundColor(DS.Colors.primary)

            Text("Reflect on your day, one conversation at a time.")
                .font(DS.font(.subheadline))
                .foregroundColor(DS.Colors.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xl)
        }
    }

    // MARK: - Register link

    private var registerLink: some View {
        NavigationLink(destination: RegisterView()) {
            Text("Create an account")
                .font(DS.font(.subheadline))
                .foregroundColor(DS.Colors.dustyBlue)
        }
    }
}

// MARK: - LoginView

struct LoginView: View {
    @EnvironmentObject var auth: AuthService

    @State private var email    = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            AuthTextField("Email",    text: $email,    keyboardType: .emailAddress)
            AuthSecureField("Password", text: $password)

            if let err = error {
                Text(err)
                    .font(DS.font(.caption))
                    .foregroundColor(DS.Colors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Spacing.xs)
            }

            AuthPrimaryButton(label: "Sign In", isLoading: isLoading) {
                Task { await signIn() }
            }
            .disabled(email.isEmpty || password.isEmpty || isLoading)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func signIn() async {
        isLoading = true
        error     = nil
        do {
            try await auth.login(email: email, password: password)
        } catch let e as HTTPError {
            error = "Sign in failed (\(e.status)). Please try again."
        } catch {
            self.error = "Sign in failed. Please check your connection."
        }
        isLoading = false
    }
}

// MARK: - RegisterView

struct RegisterView: View {
    @EnvironmentObject var auth: AuthService

    @State private var email    = ""
    @State private var password = ""
    @State private var confirm  = ""
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            JourneyBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Create Account")
                        .font(DS.fontSize(24, weight: .semibold))
                        .foregroundColor(DS.Colors.primary)
                        .padding(.top, DS.Spacing.lg)

                    Text("Start your journaling journey.")
                        .font(DS.font(.subheadline))
                        .foregroundColor(DS.Colors.secondary)
                        .padding(.bottom, DS.Spacing.sm)

                    AuthTextField("Email",                  text: $email,    keyboardType: .emailAddress)
                    AuthSecureField("Password (min 8 chars)", text: $password)
                    AuthSecureField("Confirm password",       text: $confirm)

                    if let err = error {
                        Text(err)
                            .font(DS.font(.caption))
                            .foregroundColor(DS.Colors.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Spacing.xs)
                    }

                    AuthPrimaryButton(label: "Create Account", isLoading: isLoading) {
                        Task { await createAccount() }
                    }
                    .disabled(email.isEmpty || password.isEmpty || confirm.isEmpty || isLoading)
                }
                .padding(.horizontal, DS.Spacing.lg)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func createAccount() async {
        guard password == confirm else { error = "Passwords don't match"; return }
        guard password.count >= 8  else { error = "Password must be at least 8 characters"; return }
        isLoading = true
        error     = nil
        do {
            try await auth.register(email: email, password: password)
        } catch let e as HTTPError {
            error = "Registration failed (\(e.status)). Please try again."
        } catch {
            self.error = "Registration failed. Please check your connection."
        }
        isLoading = false
    }
}

// MARK: - Shared auth UI components
// Extracted as top-level views to allow reuse across login and register screens.

/// A standard text field styled for auth forms.
struct AuthTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    init(_ placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) {
        self.placeholder  = placeholder
        self._text        = text
        self.keyboardType = keyboardType
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .font(DS.font(.body))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboardType)
            .textContentType(keyboardType == .emailAddress ? .emailAddress : .none)
            .padding(DS.Spacing.md)
            .background(DS.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Colors.backgroundAlt, lineWidth: 1)
            )
    }
}

/// A password field styled for auth forms.
struct AuthSecureField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text       = text
    }

    var body: some View {
        SecureField(placeholder, text: $text)
            .font(DS.font(.body))
            .padding(DS.Spacing.md)
            .background(DS.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Colors.backgroundAlt, lineWidth: 1)
            )
    }
}

/// A full-width primary action button with an optional loading spinner.
struct AuthPrimaryButton: View {
    let label: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(DS.Colors.onAccent)
                } else {
                    Text(label)
                        .font(DS.font(.body, weight: .semibold))
                        .foregroundColor(DS.Colors.onAccent)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(DS.Colors.dustyBlue)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
    }
}
