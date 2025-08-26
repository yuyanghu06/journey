import SwiftUI

struct AuthLandingView: View {
    @EnvironmentObject var auth: AuthService
    @State private var showingRegister = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Journey").font(.largeTitle).bold()
                Text("Welcome to the beta build of Journey! Please be mindful of any bugs you see and report them in the app.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .bold()
                Text("Sign in to continue").foregroundStyle(.secondary)

                NavigationLink("I don’t have an account", destination: RegisterView())
                LoginView()
            }
            .padding()
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var auth: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email).textInputAutocapitalization(.never)
                .autocorrectionDisabled().textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .padding().background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 12))

            SecureField("Password", text: $password)
                .padding().background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 12))

            if let err = error { Text(err).foregroundStyle(.red).font(.footnote) }

            Button {
                Task {
                    do { try await auth.login(email: email, password: password) }
                    catch let e as HTTPError {
                        self.error = "Login failed (\(e.status))"
                    } catch {
                        self.error = "Login failed"
                    }
                }
            } label: {
                HStack {
                    Spacer(); Text("Sign In").bold(); Spacer()
                }.padding().background(Color.accentColor).foregroundStyle(.white)
                 .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(email.isEmpty || password.isEmpty)
        }
        .padding()
    }
}

struct RegisterView: View {
    @EnvironmentObject var auth: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section(header: Text("Create Account")) {
                TextField("Email", text: $email).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().textContentType(.emailAddress)
                SecureField("Password (min 8)", text: $password)
                SecureField("Confirm password", text: $confirm)
            }
            if let err = error { Text(err).foregroundStyle(.red) }

            Button("Create Account") {
                Task {
                    guard password == confirm else { self.error = "Passwords don’t match"; return }
                    guard password.count >= 8 else { self.error = "Password too short"; return }
                    do { try await auth.register(email: email, password: password) }
                    catch let e as HTTPError {
                        self.error = "Register failed (\(e.status))"
                    } catch {
                        self.error = "Register failed"
                    }
                }
            }.disabled(email.isEmpty || password.isEmpty || confirm.isEmpty)
        }
        .navigationTitle("Register")
    }
}

struct RegisterView_Previews: PreviewProvider {
    static var previews: some View {
        AuthLandingView()
    }
}
