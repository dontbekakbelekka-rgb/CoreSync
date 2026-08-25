import SwiftUI

// Plain email/password login matching the web app's own login - deliberately
// not Sign in with Apple, since this needs to authenticate as the same
// Supabase account the web app uses.
struct LoginView: View {
    @EnvironmentObject private var auth: SupabaseAuth
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 4) {
                Text("CoreSync")
                    .font(.largeTitle.bold())
                Text("Sign in with your STAYINTHEFIGHT account")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if let error = auth.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                Task {
                    isSubmitting = true
                    await auth.login(email: email, password: password)
                    isSubmitting = false
                }
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Log In")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(email.isEmpty || password.isEmpty || isSubmitting)
            .padding(.horizontal)

            Spacer()
            Spacer()
        }
        .padding()
    }
}

#Preview {
    LoginView().environmentObject(SupabaseAuth())
}
