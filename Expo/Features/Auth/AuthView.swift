import SwiftUI

struct AuthView: View {
    private enum Mode: Equatable { case signIn, register, verify, requestReset, enterResetCode, newPassword }

    @Environment(AppModel.self) private var model
    @State private var mode = Mode.signIn
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var code = ""
    @State private var message = ""
    @State private var notice = ""
    @State private var busy = false
    @State private var resendIn = 0

    var body: some View {
        HStack(spacing: 0) {
            showcase
            Rectangle().fill(Theme.border).frame(width: 1)
            form
        }
        .onAppear {
            guard model.startsAtRegistration else { return }
            model.startsAtRegistration = false
            mode = .register
        }
        .task(id: resendIn) {
            guard resendIn > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { resendIn -= 1 }
        }
    }

    /// What Expo does, beside the one moving picture on this screen.
    private var showcase: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Logo(size: 24)
                Text("Expo").font(.system(size: 14, weight: .bold))
                Spacer()
                Button("Take the tour") { model.showsWelcome = true }.buttonStyle(.expo(.plain, compact: true))
            }
            .rise()
            LoopingAnimation(name: "auth-hero")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 4)
            Text("Your copilot for important conversations")
                .font(.system(size: 19, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .rise(0.08)
            VStack(alignment: .leading, spacing: 7) {
                point("waveform", "Live transcript and meeting notes").rise(0.14)
                point("sparkles", "Concise answers when you need them").rise(0.2)
                point("eye.slash", "You decide what screen shares show").rise(0.26)
            }
            .padding(.top, 11)
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 24)
        .frame(width: 330)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 11)).frame(width: 16)
            Text(text).font(.system(size: 12))
        }
        .foregroundStyle(Theme.secondary)
    }

    private var form: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.system(size: 20, weight: .bold))
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .rise(0.05)
                    VStack(alignment: .leading, spacing: 11) {
                        fields
                        if !notice.isEmpty { Text(notice).font(.system(size: 11.5)).foregroundStyle(Theme.success) }
                        if !message.isEmpty { Text(message).font(.system(size: 11.5)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true) }
                        Button { submit() } label: {
                            HStack(spacing: 6) {
                                if busy { ProgressView().controlSize(.small) }
                                Text(busy ? "Please wait…" : action)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.expo)
                        .keyboardShortcut(.defaultAction)
                        .disabled(busy)
                        .padding(.top, 2)
                        links
                    }
                    .rise(0.1)
                    if model.config?.isBackendConfigured != true {
                        Text("No backend is configured. Add your .env to ~/Library/Application Support/Expo.")
                            .font(.system(size: 11)).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 290)
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
                .animation(.snappy(duration: 0.25), value: mode)
            }
            .defaultScrollAnchor(.center)
            .scrollBounceBehavior(.basedOnSize)
            // Screen-share privacy works before there is an account.
            PrivacyRow()
                .frame(width: 290)
                .padding(.bottom, 20)
                .rise(0.18)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var fields: some View {
        switch mode {
        case .signIn, .register:
            if mode == .register {
                HStack { Field(label: "First name", text: $firstName); Field(label: "Last name", text: $lastName) }
            }
            Field(label: "Email", text: $email)
            Field(label: "Password", text: $password, secure: true)
        case .verify, .enterResetCode:
            Field(label: "6-digit code", text: $code)
        case .requestReset:
            Field(label: "Email", text: $email)
        case .newPassword:
            Field(label: "New password", text: $password, secure: true)
            Field(label: "Confirm new password", text: $confirmation, secure: true)
        }
    }

    @ViewBuilder private var links: some View {
        HStack {
            switch mode {
            case .signIn:
                Button("Create an account") { move(.register) }
                Spacer()
                Button("Forgot password?") { move(.requestReset) }
            case .register:
                Button("I already have an account") { move(.signIn) }
            case .verify, .enterResetCode:
                Button("Back to sign in") { move(.signIn) }
                Spacer()
                Button(resendIn > 0 ? "Resend in \(resendIn)s" : "Resend code") { resend() }.disabled(resendIn > 0 || busy)
            case .requestReset, .newPassword:
                Button("Back to sign in") { move(.signIn) }
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Theme.accent)
    }

    private var title: String {
        switch mode {
        case .signIn: "Welcome back"
        case .register: "Create your Expo account"
        case .verify: "Check your email"
        case .requestReset: "Reset your password"
        case .enterResetCode: "Enter your reset code"
        case .newPassword: "Choose a new password"
        }
    }

    private var subtitle: String {
        switch mode {
        case .signIn: "Sign in to continue to Expo."
        case .register: "It takes less than a minute."
        case .verify, .enterResetCode: "Enter the code sent to \(email)."
        case .requestReset: "We will email you a 6-digit code."
        case .newPassword: "Use at least 8 characters."
        }
    }

    private var action: String {
        switch mode {
        case .signIn: "Sign in"
        case .register: "Create account"
        case .verify: "Verify email"
        case .requestReset: "Send code"
        case .enterResetCode: "Verify code"
        case .newPassword: "Update password"
        }
    }

    private func move(_ next: Mode) {
        mode = next
        message = ""; notice = ""; code = ""; password = ""; confirmation = ""
    }

    private func validationProblem() -> String? {
        let emailValid = email.trimmed.wholeMatch(of: /\S+@\S+\.\S+/) != nil
        switch mode {
        case .signIn, .register:
            if mode == .register && (firstName.trimmed.isEmpty || lastName.trimmed.isEmpty) { return "Enter both names." }
            return emailValid && password.count >= 8 ? nil : "Enter a valid email and a password of at least 8 characters."
        case .requestReset: return emailValid ? nil : "Enter a valid email address."
        case .verify, .enterResetCode: return code.trimmed.wholeMatch(of: /\d{6}/) != nil ? nil : "Enter the 6-digit code from your email."
        case .newPassword:
            if password.count < 8 { return "Use at least 8 characters." }
            return password == confirmation ? nil : "The passwords do not match."
        }
    }

    private func submit() {
        guard !busy else { return }
        if let problem = validationProblem() { message = problem; return }
        message = ""; notice = ""; busy = true
        Task {
            defer { busy = false }
            do {
                switch mode {
                case .signIn:
                    if let pending = try await model.signIn(email: email, password: password) { verify(pending) }
                case .register:
                    if let pending = try await model.register(firstName: firstName, lastName: lastName, email: email, password: password) { verify(pending) }
                case .verify:
                    try await model.verifyEmail(email, code: code)
                case .requestReset:
                    let text = try await model.requestPasswordReset(email)
                    move(.enterResetCode); notice = text; resendIn = 60
                case .enterResetCode:
                    try await model.verifyPasswordReset(email, code: code)
                    move(.newPassword)
                case .newPassword:
                    try await model.completePasswordReset(password)
                    move(.signIn); notice = "Password updated. Sign in with your new password."
                }
            } catch {
                message = error.localizedDescription
                // A local server starts empty, so a refused sign-in usually means
                // the account was made on another server.
                if mode == .signIn, usesLocalServer, (error as? BackendError)?.status == 401 {
                    message += " The server on this Mac has its own accounts. If you haven’t made one here, choose Create an account."
                }
            }
        }
    }

    private var usesLocalServer: Bool {
        model.config.map { AppConfig.isLoopback($0.backendURL) } ?? false
    }

    private func verify(_ address: String) {
        email = address
        move(.verify)
        resendIn = 60
    }

    private func resend() {
        resendIn = 60
        message = ""
        Task {
            do {
                if mode == .verify { try await model.resendCode(email) }
                else { _ = try await model.requestPasswordReset(email) }
                notice = "A new code is on its way."
            } catch { message = error.localizedDescription; resendIn = 0 }
        }
    }
}
