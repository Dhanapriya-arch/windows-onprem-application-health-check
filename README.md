# Windows On-Prem Application Support Health Check

A PowerShell portfolio project for practicing first-pass troubleshooting of a Windows-hosted web application. It gathers read-only checks for DNS, TCP ports, an optional website response, Windows web services, local IIS sites/application pools, and certificates nearing expiry. It writes a timestamped JSON report.

This is a learning project. It does not install software, change IIS settings, modify certificates, restart services, or change firewall rules. Run it only on systems you own or are authorized to support. Remote service queries may require appropriate Windows permissions and firewall configuration.

## Requirements

- Windows PowerShell 5.1 on Windows (recommended)
- For IIS inventory and certificate checks: run locally on the IIS server with the IIS Management PowerShell module installed
- For useful real results: supply host names and URL for your own lab

## Run locally

Open PowerShell in this folder and run:

```powershell
.\scripts\Test-OnPremApplicationHost.ps1 -ComputerName localhost -WebPort 443
```

The script checks DNS and TCP reachability, queries W3SVC and WAS, inventories IIS and local machine certificates when run on the local server, then writes a JSON report under `reports/`.

## Check a lab application server

Replace the example names with systems in your own isolated lab:

```powershell
.\scripts\Test-OnPremApplicationHost.ps1 `
  -ComputerName "app01.example.local" `
  -DnsName "app01.example.local" `
  -WebsiteUrl "https://app01.example.local/" `
  -WebPort 443 `
  -SqlHost "sql01.example.local" `
  -SqlPort 1433
```

The script runs from your workstation. DNS and port checks run from that workstation; service status checks use the Windows remote service query. IIS website/application-pool inventory and certificate expiry checks run only when the target is the local computer. For those checks, sign in to the lab server and run the script there.

## Example lab build

1. Create an isolated Windows Server virtual machine and take a snapshot.
2. Add the IIS Web Server role using Server Manager or the Windows feature tools.
3. Create a simple test site with a dedicated folder and a test `index.html` page.
4. Add a site binding for HTTP first. If you configure HTTPS, use a certificate created for the lab and bind it in IIS. Never disable certificate validation.
5. Create a dedicated application pool and configure the test site to use it. Give its identity only the file permissions the test site needs.
6. Optionally install SQL Server Developer or Express in a separate lab VM and create a test database. Use synthetic data only.
7. Run the health check locally on the IIS server, then from your workstation for DNS, port, and URL checks. Review the JSON report.
8. Practice diagnosis by stopping a test app pool, using an incorrect test URL, or testing a closed port. Record the observed symptom, evidence, fix, and verification. Restore the VM snapshot when finished.

## Troubleshooting notes

- DNS failure: compare the name with the lab DNS record and check which DNS server the client uses.
- TCP failure: confirm the service is listening and that the lab firewall permits the port; do not turn off the firewall as a workaround.
- HTTP failure: check the site binding, app pool state, physical path, file access, and IIS logs.
- W3SVC/WAS query error: run locally or check permissions and remote service-management access.
- Certificate warning: compare the certificate's subject/SAN and expiry with the HTTPS hostname and binding.
- SQL port failure: confirm SQL TCP/IP is enabled, the configured port is correct, and the lab firewall rule is scoped appropriately.

## Limitations

This script is a first-pass checklist, not a full monitoring or security product. It does not log in to the application, test SSO flows, run SQL queries, inspect application-specific logs, or make configuration changes. It reports the checks it can perform and the error details returned by Windows/PowerShell.

## Suggested GitHub description

PowerShell first-pass health checks for Windows/IIS application support: DNS, TCP, HTTP, IIS, Windows services, and certificate expiry.

## Publish this project on GitHub

1. Extract the downloaded project ZIP on your computer.
2. Sign in to GitHub and create a new repository named `windows-onprem-application-health-check`.
3. Choose **Public** only if you are comfortable making the project source visible to everyone. Do not add credentials, customer names, real hostnames, screenshots with internal information, or generated diagnostic reports.
4. Open the new repository and choose **Add file > Upload files**.
5. Upload the contents of the extracted `windows-onprem-application-support-health-check` folder so that `README.md`, `scripts`, `config`, `.gitignore`, and `reports` appear at the repository root.
6. Enter a commit message such as `Add Windows on-prem application health check` and select **Commit changes**.
7. Open the repository page and copy its URL. Add that URL to the project entry in your resume.

Keep `reports/*.json` out of GitHub. The included `.gitignore` excludes generated reports because they can reveal machine names and environment details.

