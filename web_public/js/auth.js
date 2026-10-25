class Auth {
    constructor() {
        this.user = null;
        this.profileName = null;
        this.role = localStorage.getItem('user_role') || null;
        this.activeAddress = null; // Initialize missing property
        
        // GLOBAL ERROR CATCHER FOR DEBUGGING
        window.addEventListener('error', (e) => this.showDebugError(e.message, e.filename, e.lineno));
        window.addEventListener('unhandledrejection', (e) => this.showDebugError(e.reason?.message || e.reason, 'Promise', 0));
        
        this.init().catch(err => {
            console.error("Auth init error:", err);
            this.showDebugError("Init Error: " + (err.message || err), 'auth.js init', 0);
        });
    }

    showDebugError(msg, file, line) {
        // Debugging disabled
    }

    async init() {
        if (typeof supabaseClient === 'undefined' || !supabaseClient) {
            this.showDebugError("Supabase client not found.");
            return;
        }

        this.showDebugError("Init started. Fetching session...");
        
        let session = null;
        try {
            const result = await supabaseClient.auth.getSession();
            session = result.data.session;
            this.showDebugError("getSession returned: " + (session ? "YES" : "NO"));
            if (result.error) this.showDebugError("getSession error: " + result.error.message);
        } catch (e) {
            this.showDebugError("getSession crashed: " + e.message);
        }
        
        // Safari Private Browsing fallback
        if (!session) {
            this.showDebugError("Checking sessionStorage fallback...");
            const cachedEmail = sessionStorage.getItem('enything_fallback_email');
            const cachedPassword = sessionStorage.getItem('enything_fallback_password');
            if (cachedEmail && cachedPassword) {
                this.showDebugError("Found fallback credentials, attempting signIn...");
                const { data: authData, error: authError } = await supabaseClient.auth.signInWithPassword({
                    email: cachedEmail,
                    password: cachedPassword
                });
                if (authError) {
                    this.showDebugError("Fallback signIn error: " + authError.message);
                } else if (authData.session) {
                    this.showDebugError("Fallback signIn SUCCESS!");
                    session = authData.session;
                    // B6 FIX: Clear plaintext credentials immediately after successful re-auth
                    // to minimize exposure window in Safari Private Browsing mode.
                    sessionStorage.removeItem('enything_fallback_email');
                    sessionStorage.removeItem('enything_fallback_password');
                }
            } else {
                this.showDebugError("No fallback credentials found in sessionStorage.");
            }
        }

        this.showDebugError("Calling handleSessionState with session: " + (session ? "YES" : "NO"));
        await this.handleSessionState(session);

        supabaseClient.auth.onAuthStateChange(async (event, newSession) => {
            if (event === 'INITIAL_SESSION') return;
            this.showDebugError("Auth State Changed: " + event);
            await this.handleSessionState(newSession);
        });
    }

    async handleSessionState(session) {
        console.log("Handle Session State called with:", session ? "Session Exists" : "No Session");
        try {
            if (session) {
                this.user = session.user;
                
                // Note: role is loaded synchronously from localStorage in constructor
                console.log("Current role in localStorage:", this.role);
                
                // Fetch profile name and phone if not already fetched
                if (!this.profileName || !this.profilePhone) {
                    const { data: profile, error: profileError } = await supabaseClient
                        .from('profiles')
                        .select('full_name, phone')
                        .eq('id', session.user.id)
                        .maybeSingle();
                        
                    if (profileError) {
                        console.error("Error fetching profile:", profileError);
                    }
                        
                    if (profile && profile.full_name) {
                        this.profileName = profile.full_name;
                        console.log("Profile Name Fetched:", this.profileName);
                    } else if (session.user.user_metadata && session.user.user_metadata.full_name) {
                        this.profileName = session.user.user_metadata.full_name;
                        console.log("Profile Name from metadata:", this.profileName);
                    } else {
                        this.profileName = 'Customer';
                    }
                    
                    let extractedPhone = '';
                    if (session.user?.email && session.user.email.endsWith('@enything.com')) {
                        extractedPhone = session.user.email.split('@')[0];
                        if (extractedPhone.startsWith('mock')) {
                            extractedPhone = '+' + extractedPhone.substring(4);
                        }
                    }
                    
                    this.profilePhone = extractedPhone || session.user?.phone || session.user?.user_metadata?.phone || (profile && profile.phone) || '';
                }

                // Fetch active address for Location Bar
                if (this.role === 'customer' && !this.activeAddress) {
                    const { data: address, error: addressError } = await supabaseClient
                        .from('saved_addresses')
                        .select('label, address, location')
                        .eq('user_id', session.user.id)
                        .order('created_at', { ascending: false })
                        .limit(1)
                        .maybeSingle();
                        
                    if (addressError) {
                        console.error("Error fetching address:", addressError);
                    }
                        
                    if (address) {
                        this.activeAddress = address;
                    } else {
                        // Fallback location for reviewers or default
                        this.activeAddress = { label: 'Location', address: 'Set your delivery location' };
                    }
                }

                // 100x Realtime Single-Device Session Listener for Web Portal
                if (session && !this._sessionChannelSubscribed) {
                    this._sessionChannelSubscribed = true;
                    try {
                        supabaseClient
                            .channel(`web-profile-session-${session.user.id}`)
                            .on('postgres_changes', {
                                event: 'UPDATE',
                                schema: 'public',
                                table: 'profiles',
                                filter: `id=eq.${session.user.id}`
                            }, (payload) => {
                                const newSessionId = payload.new?.current_session_id;
                                const localSessionId = localStorage.getItem('local_session_id');
                                if (newSessionId && localSessionId && newSessionId !== localSessionId) {
                                    console.warn('[SingleDeviceAuth] Remote login detected on another device!');
                                    alert('You have been logged out because your account was logged in on another device.');
                                    this.logout();
                                }
                            })
                            .subscribe();
                    } catch (chanErr) {
                        console.warn('[SingleDeviceAuth] Failed to subscribe to session realtime:', chanErr);
                    }
                }
            } else {
                this.user = null;
                this.role = null;
                this.profileName = null;
                this.activeAddress = null;
                localStorage.removeItem('user_role');
                localStorage.removeItem('local_session_id');
            }
        } catch (err) {
            console.error("Error in handleSessionState:", err);
            // If something goes wrong fetching profile/address, we still have the session.
            // Ensure we at least show them logged in, even if data is missing.
            if (session) {
                this.user = session.user;
                if (!this.profileName) this.profileName = 'Customer';
            }
        } finally {
            this.updateUI();
        }
    }

    async sendOtp(phone) {
        if (!phone || phone.length < 10) throw new Error("Invalid phone number");
        
        const isMagicNumber = phone.endsWith('9999999996') || phone.endsWith('9999999997') || phone.endsWith('9999999998');
        if (isMagicNumber) {
            console.log("[Auth] Magic reviewer number detected. Bypassing SMS send.");
            return { success: true, message: "OTP sent (Reviewer bypass)" };
        }

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
        this.showDebugError("verifyOtp started for phone: " + phone);
        if (!otp || otp.length < 4) throw new Error("Invalid OTP");

        const isMagicNumber = phone.endsWith('9999999996') || phone.endsWith('9999999997') || phone.endsWith('9999999998');

        if (!isMagicNumber) {
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
        }

        // Generate the password from the phone number (matches _passwordFromPhone in Flutter)
        const digits = phone.replace(/\D/g, '');
        
        let email;
        if (phone.endsWith('9999999996')) email = 'mock919999999996@enything.com';
        else if (phone.endsWith('9999999997')) email = 'mock919999999997@enything.com';
        else if (phone.endsWith('9999999998')) email = 'mock919999999998@enything.com';
        else email = `${digits}@auth.enything.app`;
        
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

        this.showDebugError(`Attempting signInWithPassword for email: ${email}`);
        const { data: authData, error: authError } = await supabaseClient.auth.signInWithPassword({
            email: email,
            password: password
        });
            
        let finalUserId = null;
        if (authError) {
            this.showDebugError("Primary signIn failed: " + authError.message);
            // Attempt legacy password
            const legacyPassword = `Enything${digits}#Auth2025`;
            const { data: legacyData, error: legacyError } = await supabaseClient.auth.signInWithPassword({
                email: email,
                password: legacyPassword
            });
            if (legacyError) {
                this.showDebugError("Legacy signIn failed: " + legacyError.message + " -> Attempting signUp");
                // User doesn't exist yet, sign them up!
                const { data: signUpData, error: signUpError } = await supabaseClient.auth.signUp({
                    email: email,
                    password: password,
                    options: {
                        data: { phone: phone }
                    }
                });
                
                if (signUpError) {
                    this.showDebugError("signUp failed: " + signUpError.message);
                    throw signUpError;
                }
                finalUserId = signUpData.user.id;
                // Save credentials for Safari Private Browsing session recovery
                this.showDebugError("Saving credentials to sessionStorage (signup)");
                this._saveCredentials(email, password);
            } else {
                this.showDebugError("Legacy signIn SUCCESS!");
                finalUserId = legacyData.user.id;
                // Save credentials for Safari Private Browsing session recovery
                this.showDebugError("Saving legacy credentials to sessionStorage");
                this._saveCredentials(email, legacyPassword);
            }
        } else {
            this.showDebugError("Primary signIn SUCCESS! Session created.");
            finalUserId = authData.user.id;
            // Save credentials for Safari Private Browsing session recovery
            this.showDebugError("Saving credentials to sessionStorage");
            this._saveCredentials(email, password);
        }

        // 100x Strict Single-Device Session Enforcement for Web Portal
        try {
            const webSessionId = 'web_' + Date.now() + '_' + Math.random().toString(36).substring(2, 9);
            localStorage.setItem('local_session_id', webSessionId);
            await supabaseClient.rpc('enforce_single_device_login', {
                p_user_id: finalUserId,
                p_session_id: webSessionId,
                p_device_id: 'web_portal'
            });
        } catch (sessErr) {
            console.warn('[SingleDeviceAuth] enforce_single_device_login fallback:', sessErr);
        }
            
        this.role = role;
        localStorage.setItem('user_role', role);
        
        // Check if profile exists
        this.showDebugError("Checking if profile exists...");
        const { data: profile } = await supabaseClient
            .from('profiles')
            .select('full_name')
            .eq('id', finalUserId)
            .maybeSingle();
            
        if (profile) {
            this.showDebugError("Profile found. Returning isNewUser: false");
            return { isNewUser: false, profile: profile, userId: finalUserId };
        } else {
            this.showDebugError("Profile NOT found. Returning isNewUser: true");
            return { isNewUser: true, userId: finalUserId };
        }
    }

    async createProfile(userId, phone, fullName, role) {
        const uniquePhone = phone.includes('999999999') ? phone + Date.now().toString().slice(-4) : phone;
        const { error: profileError } = await supabaseClient.from('profiles').upsert({
            id: userId,
            role: role,
            full_name: fullName,
            phone: uniquePhone
        });
        
        if (profileError) throw profileError;

        if (role === 'customer') {
             await supabaseClient.from('customers').upsert({
                id: userId,
                location: 'POINT(74.6366 34.4225)'
             });
        }
        
        this.profileName = fullName;
        this.updateUI();
    }

    async checkAdminStatus(userId, phone = null) {
        try {
            let admin = null;
            if (userId) {
                const { data, error } = await supabaseClient
                    .from('admin_users')
                    .select('id, full_name, phone, admin_level, is_active, is_suspended, role_id, roles(id, name, slug, description, color, icon)')
                    .eq('id', userId)
                    .maybeSingle();
                if (!error && data) {
                    admin = data;
                }
            }

            if (!admin && phone) {
                const digits = phone.replace(/\D/g, '').slice(-10);
                const { data, error } = await supabaseClient
                    .from('admin_users')
                    .select('id, full_name, phone, admin_level, is_active, is_suspended, role_id, roles(id, name, slug, description, color, icon)')
                    .ilike('phone', `%${digits}%`)
                    .maybeSingle();
                if (!error && data) {
                    admin = data;
                }
            }

            if (!admin) {
                return { isAdmin: false, error: "Not found in admin_users" };
            }

            if (admin.is_suspended) {
                return { isAdmin: false, isSuspended: true, error: "Admin account is suspended." };
            }

            if (!admin.is_active) {
                return { isAdmin: false, isInactive: true, error: "Admin account is inactive." };
            }

            return { isAdmin: true, adminData: admin };
        } catch (err) {
            console.error("checkAdminStatus exception:", err);
            return { isAdmin: false, error: err.message };
        }
    }

    async verifyAdminPassword(userId, password) {
        if (!password || password.trim() === '') {
            throw new Error("Password cannot be empty.");
        }
        const { data, error } = await supabaseClient.rpc('verify_admin_password', {
            p_admin_id: userId,
            p_password: password.trim()
        });

        if (error) {
            console.error("verify_admin_password RPC error:", error);
            throw new Error("Admin password verification failed: " + error.message);
        }

        if (data === true) {
            // Log to admin_sessions to maintain mobile-web cross-platform parity
            try {
                await supabaseClient.from('admin_sessions').insert({
                    admin_id: userId,
                    device_info: 'Enything Web Admin Portal'
                });
            } catch (sessErr) {
                console.warn("Could not insert admin session:", sessErr);
            }
        }

        return data === true;
    }

    async getAdminPermissions(roleId) {
        if (!roleId) return [];
        try {
            const { data, error } = await supabaseClient
                .from('role_permissions')
                .select('permissions(code)')
                .eq('role_id', roleId);

            if (error || !data) return [];
            return data.map(rp => rp.permissions?.code).filter(Boolean);
        } catch (e) {
            console.warn("Could not fetch permissions:", e);
            return [];
        }
    }

    async recordAdminAudit(userId, action, metadata = {}) {
        try {
            await supabaseClient.from('audit_logs').insert({
                actor_id: userId,
                actor_role: 'admin',
                action: action,
                entity_type: 'system',
                metadata: { ...metadata, platform: 'web', timestamp: new Date().toISOString() }
            });
        } catch (e) {
            console.warn("Could not record audit log:", e);
        }
    }

    async logout() {
        const { error } = await supabaseClient.auth.signOut();
        try {
            sessionStorage.removeItem('enything_fallback_email');
            sessionStorage.removeItem('enything_fallback_password');
            localStorage.removeItem('local_session_id');
            localStorage.removeItem('admin_user');
            localStorage.removeItem('admin_verified');
            localStorage.removeItem('admin_permissions');
            localStorage.removeItem('user_role');
        } catch(e) {}
        if (error) throw error;
        window.location.reload();
    }

    updateUI() {
        // Find login buttons and update them
        const authContainer = document.getElementById('auth-container');
        if (authContainer) {
            if (this.user) {
                const isAdmin = localStorage.getItem('admin_verified') === 'true' || this.role === 'admin';
                const adminLink = isAdmin ? `
                    <a href="admin_dashboard.html" style="padding: 10px 16px; display: flex; align-items: center; gap: 10px; color: #818CF8; font-weight: 600; border-top: 1px solid var(--glass-border);"><i class="fas fa-shield-alt" style="width: 20px;"></i> Admin Portal</a>
                ` : '';

                authContainer.innerHTML = `
                    <div style="position: relative; display: inline-block;" class="dropdown">
                        <span style="cursor:pointer; font-weight: 600; display: flex; align-items: center; gap: 8px;">
                            <div style="width: 35px; height: 35px; background: var(--accent-color); border-radius: 50%; display: flex; align-items: center; justify-content: center; color: white; font-size: 1rem;">
                                <i class="fas fa-user"></i>
                            </div>
                        </span>
                        <div class="dropdown-content" style="right: 0; min-width: 200px; padding: 0.5rem 0; border-radius: 12px;">
                            <div style="padding: 10px 16px; border-bottom: 1px solid var(--glass-border); margin-bottom: 5px;">
                                <strong style="display: block; font-size: 1rem;">${this.profileName || 'Customer'}</strong>
                                <span style="font-size: 0.8rem; color: var(--text-muted);">${this.profilePhone || ''}</span>
                            </div>
                            <a href="orders.html" style="padding: 10px 16px; display: flex; align-items: center; gap: 10px;"><i class="fas fa-box" style="width: 20px;"></i> My Orders</a>
                            <a href="addresses.html" style="padding: 10px 16px; display: flex; align-items: center; gap: 10px;"><i class="fas fa-map-marker-alt" style="width: 20px;"></i> Addresses</a>
                            <a href="settings.html" style="padding: 10px 16px; display: flex; align-items: center; gap: 10px;"><i class="fas fa-cog" style="width: 20px;"></i> Settings</a>
                            <a href="contact.html" style="padding: 10px 16px; display: flex; align-items: center; gap: 10px;"><i class="fas fa-headset" style="width: 20px;"></i> Support</a>
                            ${adminLink}
                            <a href="#" onclick="auth.logout(); return false;" style="color: #ef4444; padding: 10px 16px; display: flex; align-items: center; gap: 10px; border-top: 1px solid var(--glass-border); margin-top: 5px;"><i class="fas fa-sign-out-alt" style="width: 20px;"></i> Logout</a>
                        </div>
                    </div>
                `;
            } else {
                authContainer.innerHTML = `
                    <a href="login.html" class="btn" style="background: rgba(255,255,255,0.1); color: white; padding: 8px 16px; border-radius: 8px; text-decoration: none; font-weight: 600; border: 1px solid rgba(255,255,255,0.2);">Login</a>
                `;
            }
        }

        // Render Location Bar if logged in as customer
        const locationContainer = document.getElementById('location-container');
        if (locationContainer) {
            if (this.user && this.role === 'customer') {
                locationContainer.innerHTML = `
                    <div style="display: flex; align-items: center; gap: 8px; cursor: pointer;" onclick="window.location.href='addresses.html'">
                        <div style="background: rgba(91, 139, 255, 0.1); width: 35px; height: 35px; border-radius: 50%; display: flex; align-items: center; justify-content: center; color: #5B8BFF;">
                            <i class="fas fa-map-marker-alt"></i>
                        </div>
                        <div style="display: flex; flex-direction: column;">
                            <span style="font-size: 0.8rem; font-weight: 700; color: #5B8BFF; text-transform: uppercase; display: flex; align-items: center; gap: 4px;">
                                ${(this.activeAddress && this.activeAddress.label) ? this.activeAddress.label : 'Delivery Location'} <i class="fas fa-chevron-down" style="font-size: 0.6rem;"></i>
                            </span>
                            <span style="font-size: 0.85rem; color: var(--text-muted); max-width: 150px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">
                                ${(this.activeAddress && this.activeAddress.address) ? this.activeAddress.address : 'Select a location'}
                            </span>
                        </div>
                    </div>
                `;
            } else {
                locationContainer.innerHTML = '';
            }
        }
    }
    
    _saveCredentials(email, password) {
        try {
            sessionStorage.setItem('enything_fallback_email', email);
            sessionStorage.setItem('enything_fallback_password', password);
        } catch (e) {
            console.warn("Could not save fallback credentials to sessionStorage", e);
        }
    }
}

const auth = new Auth();
window.addEventListener('DOMContentLoaded', () => {
    // We don't just updateUI once here. The async init() inside Auth constructor 
    // will trigger updateUI() when it finishes fetching the session state.
    // This is just a fallback in case init() is very fast or very slow.
    if (!auth.user) {
        auth.updateUI();
    }
});
