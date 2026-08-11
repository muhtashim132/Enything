class Auth {
    constructor() {
        this.user = null;
        this.profileName = null;
        this.role = localStorage.getItem('user_role') || null;
        this.init();
    }

    async init() {
        if (!window.supabaseClient) {
            console.error("Supabase client not found.");
            return;
        }

        const { data: { session } } = await supabaseClient.auth.getSession();
        if (session) {
            this.user = session.user;
            
            // Fetch profile name
            const { data: profile } = await supabaseClient
                .from('profiles')
                .select('full_name')
                .eq('id', session.user.id)
                .single();
                
            if (profile) {
                this.profileName = profile.full_name;
            }
        }
        this.updateUI();

        supabaseClient.auth.onAuthStateChange((_event, session) => {
            if (session) {
                this.user = session.user;
            } else {
                this.user = null;
                this.role = null;
                localStorage.removeItem('user_role');
            }
            this.updateUI();
        });
    }

    async sendOtp(phone) {
        if (!phone || phone.length < 10) throw new Error("Invalid phone number");
        
        // Match the Flutter app logic: call the send-otp edge function
        const { data, error } = await supabaseClient.functions.invoke('send-otp', {
            body: { phone: phone }
        });
        
        if (error) {
            console.error("Error sending OTP:", error);
            throw new Error(error.message || "Failed to send OTP");
        }
        return data;
    }

    async verifyOtp(phone, otp, role) {
        if (!otp || otp.length < 4) throw new Error("Invalid OTP");

        // Match the Flutter app logic: call the verify-otp edge function
        const { data: verifyData, error: verifyError } = await supabaseClient.functions.invoke('verify-otp', {
            body: { phone: phone, otp: otp }
        });

        if (verifyError) {
            console.error("Error verifying OTP:", verifyError);
            throw new Error(verifyError.message || "Invalid OTP");
        }
        
        if (verifyData && verifyData.error) {
            throw new Error(verifyData.error);
        }

        // Generate the password from the phone number (matches _passwordFromPhone in Flutter)
        const digits = phone.replace(/\D/g, '');
        const email = `${digits}@auth.enything.app`;
        
        let password;
        if (phone.endsWith('9999999996') || phone.endsWith('9999999997') || phone.endsWith('9999999998')) {
            password = 'Dummy123';
        } else {
            const message = `Enything_${digits}_Secured#2026`;
            const msgBuffer = new TextEncoder().encode(message);
            const hashBuffer = await crypto.subtle.digest('SHA-256', msgBuffer);
            const hashArray = Array.from(new Uint8Array(hashBuffer));
            const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
            password = `EnY$${hashHex.substring(0, 16)}`;
        }

        const { data: authData, error: authError } = await supabaseClient.auth.signInWithPassword({
            email: email,
            password: password
        });
            
        if (authError) {
            // Attempt legacy password
            const legacyPassword = `Enything${digits}#Auth2025`;
            const { data: legacyData, error: legacyError } = await supabaseClient.auth.signInWithPassword({
                email: email,
                password: legacyPassword
            });
            if (legacyError) {
                // User doesn't exist yet, sign them up!
                const { data: signUpData, error: signUpError } = await supabaseClient.auth.signUp({
                    email: email,
                    password: password,
                    options: {
                        data: { phone: phone }
                    }
                });
                
                if (signUpError) throw signUpError;
                
                // Create profile for new user
                const userId = signUpData.user.id;
                const uniquePhone = phone.includes('999999999') ? phone + Date.now().toString().slice(-4) : phone;
                await supabaseClient.from('profiles').upsert({
                    id: userId,
                    role: role,
                    full_name: 'New User',
                    phone: uniquePhone
                });

                if (role === 'customer') {
                     await supabaseClient.from('customers').upsert({
                        id: userId,
                        location: 'POINT(74.6366 34.4225)'
                     });
                }
                
                this.role = role;
                localStorage.setItem('user_role', role);
                return signUpData;
            }
            this.role = role;
            localStorage.setItem('user_role', role);
            return legacyData;
        }
            
        this.role = role;
        localStorage.setItem('user_role', role);
        return authData;
    }

    async logout() {
        const { error } = await supabaseClient.auth.signOut();
        if (error) throw error;
        window.location.reload();
    }

    updateUI() {
        // Find login buttons and update them
        const authContainer = document.getElementById('auth-container');
        if (authContainer) {
            if (this.user) {
                authContainer.innerHTML = `
                    <div style="position: relative; display: inline-block;" class="dropdown">
                        <span style="cursor:pointer; font-weight: 600; display: flex; align-items: center; gap: 8px;">
                            <div style="width: 30px; height: 30px; background: var(--accent-color); border-radius: 50%; display: flex; align-items: center; justify-content: center; color: white;">
                                <i class="fas fa-user"></i>
                            </div>
                            ${this.profileName ? `<span style="margin-left: 5px;">${this.profileName.split(' ')[0]}</span>` : ''}
                        </span>
                        <div class="dropdown-content" style="right: 0; min-width: 150px;">
                            <a href="#" onclick="auth.logout(); return false;" style="color: #ef4444;">Logout</a>
                        </div>
                    </div>
                `;
            } else {
                authContainer.innerHTML = `
                    <a href="login.html" class="btn" style="background: rgba(255,255,255,0.1); color: white; padding: 8px 16px; border-radius: 8px; text-decoration: none; font-weight: 600; border: 1px solid rgba(255,255,255,0.2);">Login</a>
                `;
            }
        }
    }
}

const auth = new Auth();
window.addEventListener('DOMContentLoaded', () => {
    auth.updateUI();
});
