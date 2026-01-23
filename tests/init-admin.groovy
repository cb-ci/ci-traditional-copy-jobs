import jenkins.model.*
import hudson.security.*
import jenkins.security.*

def instance = Jenkins.getInstance()

log = java.util.logging.Logger.getLogger("init-admin.groovy")
log.info("Checking if admin user needs creation...")

if (!(instance.getSecurityRealm() instanceof HudsonPrivateSecurityRealm)) {
    log.info("Creating admin user 'admin' with token 'admin_token'...")
    def hudsonRealm = new HudsonPrivateSecurityRealm(false)
    hudsonRealm.createAccount("admin", "admin_token")
    instance.setSecurityRealm(hudsonRealm)

    def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
    instance.setAuthorizationStrategy(strategy)
    instance.save()
    log.info("Admin user created successfully.")
} else {
    log.info("Security realm already configured.")
}
