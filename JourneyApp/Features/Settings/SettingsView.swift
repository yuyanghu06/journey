import SwiftUI

// MARK: - SettingsView
// Profile and app settings screen. Allows viewing and editing the user's
// display name, viewing account info, and logging out.

struct SettingsView: View {
    @EnvironmentObject var auth: AuthService
    @State private var editedName: String = ""
    @State private var isEditingName: Bool = false
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        ZStack {
            JourneyBackground()
            ScrollView {
                VStack(spacing: DS.Spacing.lg) {
                    profileSection
                    accountSection
                    logoutSection
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.lg)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            editedName = auth.userName ?? ""
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Profile")
                .font(DS.font(.subheadline, weight: .semibold))
                .foregroundColor(DS.Colors.secondary)

            VStack(spacing: 0) {
                HStack {
                    JourneyAvatar(size: 56)
                    Spacer().frame(width: DS.Spacing.md)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        if isEditingName {
                            TextField("Your name", text: $editedName)
                                .font(DS.font(.body, weight: .medium))
                                .foregroundColor(DS.Colors.primary)
                                .textInputAutocapitalization(.words)
                                .focused($nameFieldFocused)
                                .onSubmit { saveName() }
                        } else {
                            Text(auth.userName ?? "Add your name")
                                .font(DS.font(.body, weight: .medium))
                                .foregroundColor(auth.userName == nil ? DS.Colors.secondary : DS.Colors.primary)
                        }
                        if let email = auth.email {
                            Text(email)
                                .font(DS.font(.caption))
                                .foregroundColor(DS.Colors.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        if isEditingName {
                            saveName()
                        } else {
                            isEditingName = true
                            nameFieldFocused = true
                        }
                    } label: {
                        Text(isEditingName ? "Done" : "Edit")
                            .font(DS.font(.subheadline, weight: .medium))
                            .foregroundColor(DS.Colors.dustyBlue)
                    }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Account")
                .font(DS.font(.subheadline, weight: .semibold))
                .foregroundColor(DS.Colors.secondary)

            VStack(spacing: 0) {
                settingsRow(label: "Email", value: auth.email ?? "—")
                Divider().padding(.leading, DS.Spacing.md)
                settingsRow(label: "User ID", value: String(auth.userId?.prefix(8) ?? "—") + "…")
            }
            .background(DS.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
    }

    // MARK: - Logout Section

    private var logoutSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Button {
                Task { await auth.logout() }
            } label: {
                HStack {
                    Spacer()
                    Text("Sign Out")
                        .font(DS.font(.body, weight: .medium))
                        .foregroundColor(DS.Colors.error)
                    Spacer()
                }
                .padding(DS.Spacing.md)
                .background(DS.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            }
        }
        .padding(.top, DS.Spacing.md)
    }

    // MARK: - Helpers

    private func settingsRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DS.font(.body))
                .foregroundColor(DS.Colors.primary)
            Spacer()
            Text(value)
                .font(DS.font(.body))
                .foregroundColor(DS.Colors.secondary)
        }
        .padding(DS.Spacing.md)
    }

    private func saveName() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        auth.updateUserName(trimmed)
        isEditingName = false
        nameFieldFocused = false
    }
}
