# Setup Release Signing for Google Play

## Step 1: Create a Keystore File

1. **Open Terminal**
   - Navigate to your android directory:
   ```bash
   cd "/Volumes/Business and Development/Decenternet/Acent-Messenger/acent-app/android"
   ```

2. **Generate Keystore**
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

3. **Fill in the Information**
   - **Keystore password**: Create a strong password (save this!)
   - **Re-enter password**: Enter the same password
   - **What is your first and last name?**: Your name or company name
   - **What is the name of your organizational unit?**: Your department (e.g., "Development")
   - **What is the name of your organization?**: Your company name
   - **What is the name of your City or Locality?**: Your city
   - **What is the name of your State or Province?**: Your state
   - **What is the two-letter country code for this unit?**: Your country code (e.g., "US")

4. **Confirm**
   - Type "yes" to confirm

5. **Enter Key Password**
   - Press Enter to use the same password as keystore (recommended)
   - Or enter a different password (remember it!)

**Important**: Save the keystore password and alias name securely! You'll need them later.

## Step 2: Create key.properties File

1. **Create the File**
   ```bash
   cd "/Volumes/Business and Development/Decenternet/Acent-Messenger/acent-app/android"
   touch key.properties
   ```

2. **Add Your Keystore Information**
   Open `key.properties` and add:
   ```
   storePassword=YOUR_KEYSTORE_PASSWORD
   keyPassword=YOUR_KEY_PASSWORD
   keyAlias=upload
   storeFile=upload-keystore.jks
   ```

   Replace:
   - `YOUR_KEYSTORE_PASSWORD` with the password you created
   - `YOUR_KEY_PASSWORD` with the key password (same as keystore if you pressed Enter)

3. **Add to .gitignore**
   Make sure `key.properties` and `upload-keystore.jks` are in `.gitignore`:
   ```
   android/key.properties
   android/upload-keystore.jks
   ```

## Step 3: Update build.gradle.kts

✅ **Already Done!** The `build.gradle.kts` file has been updated to use the keystore for signing.

## Step 4: Verify .gitignore

Make sure your keystore files are not committed to git. Check `android/.gitignore` includes:
```
*.jks
*.keystore
key.properties
```

## Step 5: Build Release App Bundle

1. **Build the Release Version**
   ```bash
   cd "/Volumes/Business and Development/Decenternet/Acent-Messenger/acent-app"
   flutter build appbundle --release
   ```

2. **Find Your Build**
   - Location: `build/app/outputs/bundle/release/app-release.aab`
   - This is now properly signed with your release keystore!

## Step 6: Upload to Google Play Console

1. Go to: **Test and release** → **Internal testing**
2. Click **"Create new release"**
3. Upload `app-release.aab`
4. This time it should accept it (properly signed!)

## Troubleshooting

**If build fails:**
- Make sure `key.properties` file exists in `android/` directory
- Verify passwords in `key.properties` are correct
- Check that `upload-keystore.jks` exists in `android/` directory

**If "keystore not found":**
- Make sure you're in the `android/` directory when creating the keystore
- Verify the path in `key.properties` is correct: `storeFile=upload-keystore.jks`

**If password error:**
- Double-check passwords in `key.properties` match what you entered when creating keystore
- Make sure there are no extra spaces in `key.properties`

