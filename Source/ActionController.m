/*
 Copyright © Roman Zechmeister, 2014
 
 Diese Datei ist Teil von GPG Keychain Access.
 
 GPG Keychain Access ist freie Software. Sie können es unter den Bedingungen
 der GNU General Public License, wie von der Free Software Foundation
 veröffentlicht, weitergeben und/oder modifizieren, entweder gemäß
 Version 3 der Lizenz oder (nach Ihrer Option) jeder späteren Version.
 
 Die Veröffentlichung von GPG Keychain Access erfolgt in der Hoffnung, daß es Ihnen
 von Nutzen sein wird, aber ohne irgendeine Garantie, sogar ohne die implizite
 Garantie der Marktreife oder der Verwendbarkeit für einen bestimmten Zweck.
 Details finden Sie in der GNU General Public License.
 
 Sie sollten ein Exemplar der GNU General Public License zusammen mit diesem
 Programm erhalten haben. Falls nicht, siehe <http://www.gnu.org/licenses/>.
 */

#import "ActionController.h"
#import "ActionController_Private.h"
#import "KeychainController.h"
#import "SheetController.h"
#import "AppDelegate.h"


@implementation ActionController
@synthesize progressText, errorText;


#pragma mark "Import and Export"
- (IBAction)exportKey:(id)sender {
	NSSet *keys = [self selectedKeys];
	if (keys.count == 0) {
		return;
	}
	
	sheetController.title = nil; //TODO
	sheetController.msgText = nil; //TODO
	
	if ([keys count] == 1) {
		sheetController.pattern = [[keys anyObject] shortKeyID];
	} else {
		sheetController.pattern = localized(@"untitled");
	}
	
	[keys enumerateObjectsUsingBlock:^(GPGKey *key, BOOL *stop) {
		if (key.secret) {
			sheetController.allowSecretKeyExport = YES;
			*stop = YES;
		}
	}];
	
	sheetController.allowedFileTypes = [NSArray arrayWithObjects:@"asc", nil];
	sheetController.sheetType = SheetTypeExportKey;
	if ([sheetController runModalForWindow:mainWindow] != NSOKButton) {
		return;
	}
	
	self.progressText = localized(@"ExportKey_Progress");
	self.errorText = localized(@"ExportKey_Error");
	gpgc.useArmor = sheetController.exportFormat != 0;
	gpgc.userInfo = @{@"action": @(SaveDataToURLAction), @"URL": sheetController.URL, @"hideExtension": @(sheetController.hideExtension)};
	[gpgc exportKeys:keys allowSecret:sheetController.allowSecretKeyExport fullExport:NO];
}
- (IBAction)importKey:(id)sender {
	sheetController.title = nil; //TODO
	sheetController.msgText = nil; //TODO
	//sheetController.allowedFileTypes = [NSArray arrayWithObjects:@"asc", @"gpg", @"pgp", @"key", @"gpgkey", nil];
	
	sheetController.sheetType = SheetTypeOpenPanel;
	if ([sheetController runModalForWindow:mainWindow] != NSOKButton) {
		return;
	}
	
	[self importFromURLs:sheetController.URLs];
}
- (void)importFromURLs:(NSArray *)urls {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSMutableData *dataToImport = [NSMutableData data];
	
	for (NSObject *url in urls) {
		if ([url isKindOfClass:[NSURL class]]) {
			[dataToImport appendData:[NSData dataWithContentsOfURL:(NSURL *)url]];
		} else if ([url isKindOfClass:[NSString class]]) {
			[dataToImport appendData:[NSData dataWithContentsOfFile:(NSString *)url]];
		}
	}
	[self importFromData:dataToImport];
	[pool drain];
}
- (void)importFromData:(NSData *)data {
	__block BOOL containsRevSig = NO;
	__block BOOL containsImportable = NO;
	__block BOOL containsNonImportable = NO;
	__block NSMutableArray *keys = nil;
	
	
	[GPGPacket enumeratePacketsWithData:data block:^(GPGPacket *packet, BOOL *stop) {
		switch (packet.type) {
			case GPGSignaturePacket:
				switch (packet.signatureType) {
					case GPGBinarySignature:
					case GPGTextSignature:
						containsNonImportable = YES;
						break;
					case GPGRevocationSignature: {
						if (!keys) {
							keys = [NSMutableArray array];
						}
						GPGKey *key = [[[GPGKeyManager sharedInstance] keysByKeyID] objectForKey:packet.keyID];
						[keys addObject:key ? key : packet.keyID];
						containsRevSig = YES;
					} /* no break */
					case GPGGeneriCertificationSignature:
					case GPGPersonaCertificationSignature:
					case GPGCasualCertificationSignature:
					case GPGPositiveCertificationSignature:
					case GPGSubkeyBindingSignature:
					case GPGKeyBindingSignature:
					case GPGDirectKeySignature:
					case GPGSubkeyRevocationSignature:
					case GPGCertificationRevocationSignature:
						containsImportable = YES;
					default:
						break;
				}
				break;
			case GPGSecretKeyPacket:
			case GPGPublicKeyPacket:
			case GPGSecretSubkeyPacket:
			case GPGUserIDPacket:
			case GPGPublicSubkeyPacket:
			case GPGUserAttributePacket:
				containsImportable = YES;
				break;
			case GPGPublicKeyEncryptedSessionKeyPacket:
			case GPGSymmetricEncryptedSessionKeyPacket:
			case GPGSymmetricEncryptedDataPacket:
			case GPGSymmetricEncryptedProtectedDataPacket:
			case GPGCompressedDataPacket:
				containsNonImportable = YES;
				break;
			default:
				break;
		}
	}];
	
	if (containsRevSig) {
		if ([self warningSheet:@"ImportRevSig", [self descriptionForKeys:keys withOptions:0]] == NO) {
			return;
		}
	}
	
	
	self.progressText = localized(@"ImportKey_Progress");
	gpgc.userInfo = @{@"action": @(ShowResultAction), @"operation": @(ImportOperation), @"containsImportable": @(containsImportable), @"containsNonImportable": @(containsNonImportable)};
	[gpgc importFromData:data fullImport:NO];
}
- (IBAction)copy:(id)sender {
	NSString *stringForPasteboard = nil;
	
	NSResponder *responder = mainWindow.firstResponder;
	
	if (responder == appDelegate.userIDTable) {
		if (userIDsController.selectedObjects.count == 1) {
			GPGUserID *userID = [userIDsController.selectedObjects objectAtIndex:0];
			stringForPasteboard = userID.userIDDescription;
		}
	} else if (responder == appDelegate.signatureTable) {
		if (signaturesController.selectedObjects.count == 1) {
			GPGUserIDSignature *signature = [signaturesController.selectedObjects objectAtIndex:0];
			stringForPasteboard = signature.keyID;
		}
	} else if (responder == appDelegate.subkeyTable) {
		if (subkeysController.selectedObjects.count == 1) {
			GPGKey *subkey = [subkeysController.selectedObjects objectAtIndex:0];
			stringForPasteboard = subkey.keyID;
		}
	} else {
		NSSet *keys = [self selectedKeys];
		if (keys.count > 0) {
			gpgc.async = NO;
			gpgc.useArmor = YES;
			stringForPasteboard = [[gpgc exportKeys:keys allowSecret:NO fullExport:NO] gpgString];
			gpgc.async = YES;
		}
	}
	
	
	if ([stringForPasteboard length] > 0) {
		NSPasteboard *pboard = [NSPasteboard generalPasteboard];
		[pboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:self];
		[pboard setString:stringForPasteboard forType:NSStringPboardType];
	}
	
}
- (IBAction)paste:(id)sender {
	
	NSPasteboard *pboard = [NSPasteboard generalPasteboard];
	NSArray *types = [pboard types];
	if ([types containsObject:NSFilenamesPboardType]) {
		NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
		[self importFromURLs:files];
	} else if ([types containsObject:NSStringPboardType]) {
		NSData *data = [pboard dataForType:NSStringPboardType];
		if (data) {
			[self importFromData:data];
		}
	}
}


#pragma mark "Window and display"
- (IBAction)refreshDisplayedKeys:(id)sender {
	[[GPGKeyManager sharedInstance] loadAllKeys];
}

#pragma mark "Keys"
- (IBAction)generateNewKey:(id)sender {
	sheetController.sheetType = SheetTypeNewKey;
	sheetController.autoUpload = NO;
	if ([sheetController runModalForWindow:mainWindow] != NSOKButton) {
		return;
	}
	NSInteger keyType, subkeyType;
	
	switch (sheetController.keyType) {
		default:
		case 1: //RSA und RSA
			keyType = GPG_RSAAlgorithm;
			subkeyType = GPG_RSAAlgorithm;
			break;
		case 2: //DSA und Elgamal
			keyType = GPG_DSAAlgorithm;
			subkeyType = GPG_ElgamalEncryptOnlyAlgorithm;
			break;
		case 3: //DSA
			keyType = GPG_DSAAlgorithm;
			subkeyType = 0;
			break;
		case 4: //RSA
			keyType = GPG_RSAAlgorithm;
			subkeyType = 0;
			break;
	}
	self.progressText = localized(@"GenerateKey_Progress");
	self.errorText = localized(@"GenerateKey_Error");
	
	if (sheetController.autoUpload) {
		gpgc.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:UploadKeyAction], @"action", nil];
	}
	
	
	[gpgc generateNewKeyWithName:sheetController.name
						   email:sheetController.email
						 comment:sheetController.comment
						 keyType:keyType
					   keyLength:sheetController.length
					  subkeyType:subkeyType
					subkeyLength:sheetController.length
					daysToExpire:sheetController.daysToExpire
					 preferences:nil
					  passphrase:sheetController.passphrase];
}
- (IBAction)deleteKey:(id)sender {
	NSSet *keys = [self selectedKeys];
	if (keys.count == 0) {
		return;
	}
	
	NSInteger returnCode;
	BOOL applyToAll = NO;
	NSMutableSet *keysToDelete = [NSMutableSet setWithCapacity:keys.count];
	NSMutableSet *secretKeysToDelete = [NSMutableSet setWithCapacity:keys.count];
	
	[self.undoManager beginUndoGrouping];
	
	
	BOOL (^secretKeyTest)(id, BOOL*) = ^BOOL(id obj, BOOL *stop) {
		return ((GPGKey *)obj).secret;
	};
	
	
	
	NSSet *secretKeys = [keys objectsWithOptions:NSEnumerationConcurrent passingTest:secretKeyTest];
	NSMutableSet *publicKeys = [[keys mutableCopy] autorelease];
	[publicKeys minusSet:secretKeys];
	
	
	
	for (GPGKey *key in secretKeys) {
		if (!applyToAll) {
			returnCode = [sheetController alertSheetForWindow:mainWindow
												  messageText:localized(@"DeleteSecretKey_Title")
													 infoText:[NSString stringWithFormat:localized(@"DeleteSecretKey_Msg"), [key userIDDescription], key.keyID.shortKeyID]
												defaultButton:localized(@"Delete secret key only")
											  alternateButton:localized(@"Cancel")
												  otherButton:localized(@"Delete both")
											suppressionButton:localized(@"Apply to all")];
			
			applyToAll = !!(returnCode & SheetSuppressionButton);
			returnCode = returnCode & ~SheetSuppressionButton;
			if (applyToAll && returnCode == NSAlertSecondButtonReturn) {
				break;
			}
		}
		
		switch (returnCode) {
			case NSAlertFirstButtonReturn:
				[secretKeysToDelete addObject:key];
				break;
			case NSAlertThirdButtonReturn:
				[keysToDelete addObject:key];
				break;
		}
	}
	
	
	if (applyToAll && returnCode == NSAlertThirdButtonReturn) {
		returnCode = NSAlertFirstButtonReturn;
	} else {
		applyToAll = NO;
	}
	
	for (GPGKey *key in publicKeys) {
		if (!applyToAll) {
			returnCode = [sheetController alertSheetForWindow:mainWindow
												  messageText:localized(@"DeleteKey_Title")
													 infoText:[NSString stringWithFormat:localized(@"DeleteKey_Msg"), [key userIDDescription], key.keyID.shortKeyID]
												defaultButton:localized(@"Delete key")
											  alternateButton:localized(@"Cancel")
												  otherButton:nil
											suppressionButton:localized(@"Apply to all")];
			
			applyToAll = !!(returnCode & SheetSuppressionButton);
			returnCode = returnCode & ~SheetSuppressionButton;
			if (applyToAll && returnCode == NSAlertSecondButtonReturn) {
				break;
			}
		}
		
		if (returnCode == NSAlertFirstButtonReturn) {
			[keysToDelete addObject:key];
		}
	}
	
	
	if (secretKeysToDelete.count > 0) {
		self.progressText = localized(@"DeleteKeys_Progress");
		self.errorText = localized(@"DeleteKeys_Error");
		[gpgc deleteKeys:secretKeysToDelete withMode:GPGDeleteSecretKey];
	}
	
	if (keysToDelete.count > 0) {
		self.progressText = localized(@"DeleteKeys_Progress");
		self.errorText = localized(@"DeleteKeys_Error");
		[gpgc deleteKeys:keysToDelete withMode:GPGDeletePublicAndSecretKey];
	}
	
	
	[self.undoManager endUndoGrouping];
	[self.undoManager setActionName:localized(@"Undo_Delete")];
	
}

#pragma mark "Key attributes"
- (IBAction)changePassphrase:(id)sender {
	NSSet *keys = [self selectedKeys];
	if ([keys count] == 1) {
		GPGKey *key = [[keys anyObject] primaryKey];
		
		self.progressText = localized(@"ChangePassphrase_Progress");
		self.errorText = localized(@"ChangePassphrase_Error");
		[gpgc changePassphraseForKey:key];
	}
}
- (IBAction)setDisabled:(id)sender {
	NSSet *keys = [self selectedKeys];
	BOOL disabled = [sender state] == NSOnState;
	[self setDisabled:disabled forKeys:keys];
}
- (void)setDisabled:(BOOL)disabled forKeys:(NSSet *)keys {
	if (keys.count == 0) {
		return;
	}
	self.progressText = localized(@"SetDisabled_Progress");
	self.errorText = localized(@"SetDisabled_Error");
	
	GPGKey *key = keys.anyObject;
	
	if (keys.count > 1) {
		if (![keys isKindOfClass:[NSMutableSet class]]) {
			keys = [keys mutableCopy];
		}
		[(NSMutableSet *)keys removeObject:key];
		
		gpgc.userInfo = @{@"action": @(SetDisabledAction), @"keys": keys, @"disabled": @(disabled)};
	}
	
	[gpgc key:key setDisabled:disabled];
}
- (IBAction)setTrust:(NSPopUpButton *)sender {
	NSSet *keys = [self selectedKeys];
	NSInteger trust = sender.selectedTag;
	[self setTrust:trust forKeys:keys];
}
- (void)setTrust:(NSInteger)trust forKeys:(NSSet *)keys {
	if (keys.count == 0) {
		return;
	}
	self.progressText = localized(@"SetOwnerTrust_Progress");
	self.errorText = localized(@"SetOwnerTrust_Error");
	
	GPGKey *key = keys.anyObject;
	
	if (keys.count > 1) {
		if (![keys isKindOfClass:[NSMutableSet class]]) {
			keys = [keys mutableCopy];
		}
		[(NSMutableSet *)keys removeObject:key];
		
		gpgc.userInfo = @{@"action": @(SetTrustAction), @"keys": keys, @"trust": @(trust)};
	}
	
	[gpgc key:key setOwnerTrust:trust];
}

- (IBAction)changeExpirationDate:(id)sender {
	NSSet *keys = [self selectedKeys];
	if ([keys count] != 1) {
		return;
	}
	GPGKey *subkey = nil;
	GPGKey *key = [[keys anyObject] primaryKey];
	
	if ([sender tag] == 1 && [[subkeysController selectedObjects] count] == 1) {
		subkey = [[subkeysController selectedObjects] objectAtIndex:0];
	}
	
	if (subkey) {
		sheetController.msgText = [NSString stringWithFormat:localized(@"ChangeSubkeyExpirationDate_Msg"), subkey.keyID.shortKeyID, [key userIDDescription], key.keyID.shortKeyID];
		sheetController.expirationDate = [subkey expirationDate];
	} else {
		sheetController.msgText = [NSString stringWithFormat:localized(@"ChangeExpirationDate_Msg"), [key userIDDescription], key.keyID.shortKeyID];
		sheetController.expirationDate = [key expirationDate];
	}
	
	sheetController.sheetType = SheetTypeExpirationDate;
	if ([sheetController runModalForWindow:mainWindow] == NSOKButton) {
		self.progressText = localized(@"ChangeExpirationDate_Progress");
		self.errorText = localized(@"ChangeExpirationDate_Error");
		[gpgc setExpirationDateForSubkey:subkey fromKey:key daysToExpire:sheetController.daysToExpire];
	}
}
- (IBAction)editAlgorithmPreferences:(id)sender {
	NSSet *keys = [self selectedKeys];
	if ([keys count] != 1) {
		return;
	}
	GPGKey *key = [[keys anyObject] primaryKey];
	
	
	NSArray *algorithmPreferences = [gpgc algorithmPreferencesForKey:key];
		
	NSMutableArray *mutablePreferences = [NSMutableArray array];
	for (NSDictionary *prefs in algorithmPreferences) {
		NSMutableDictionary *tempPrefs = [prefs mutableCopy];
		[mutablePreferences addObject:tempPrefs];
		[tempPrefs release];
	}
	
	
	
	sheetController.allowEdit = key.secret;
	sheetController.algorithmPreferences = mutablePreferences;
	sheetController.sheetType = SheetTypeAlgorithmPreferences;
	if ([sheetController runModalForWindow:mainWindow] != NSOKButton) {
		return;
	}
	
	
	NSArray *newPreferences = sheetController.algorithmPreferences;
	
	NSUInteger count = algorithmPreferences.count;
	for (NSUInteger i = 0; i < count; i++) {
		NSDictionary *oldPrefs = [algorithmPreferences objectAtIndex:i];
		NSDictionary *newPrefs = [newPreferences objectAtIndex:i];
		if (![oldPrefs isEqualToDictionary:newPrefs]) {
			NSString *userIDDescription = [newPrefs objectForKey:@"userIDDescription"];
			NSString *cipherPreferences = [[newPrefs objectForKey:@"cipherPreferences"] componentsJoinedByString:@" "];
			NSString *digestPreferences = [[newPrefs objectForKey:@"digestPreferences"] componentsJoinedByString:@" "];
			NSString *compressPreferences = [[newPrefs objectForKey:@"compressPreferences"] componentsJoinedByString:@" "];
			
			self.progressText = localized(@"SetAlgorithmPreferences_Progress");
			self.errorText = localized(@"SetAlgorithmPreferences_Error");
			[gpgc setAlgorithmPreferences:[NSString stringWithFormat:@"%@ %@ %@", cipherPreferences, digestPreferences, compressPreferences] forUserID:userIDDescription ofKey:key];
		}
	}
}

#pragma mark "Keys (other)"
- (IBAction)cleanKey:(id)sender {
	NSSet *keys = [self selectedKeys];
	
	self.progressText = localized(@"CleanKey_Progress");
	self.errorText = localized(@"CleanKey_Error");

	[gpgc cleanKeys:keys];
}
- (IBAction)minimizeKey:(id)sender {
	NSSet *keys = [self selectedKeys];
	
	self.progressText = localized(@"MinimizeKey_Progress");
	self.errorText = localized(@"MinimizeKey_Error");
	[gpgc minimizeKeys:keys];
}
- (IBAction)genRevokeCertificate:(id)sender {
	NSSet *keys = [self selectedKeys];
	if ([keys count] != 1) {
		return;
	}
	GPGKey *key = [[keys anyObject] primaryKey];
	
	
	sheetController.title = nil; //TODO
	sheetController.msgText = nil; //TODO
	sheetController.allowedFileTypes = [NSArray arrayWithObjects:@"asc", nil];
	sheetController.pattern = [NSString stringWithFormat:localized(@"%@ Revoke certificate"), key.keyID.shortKeyID];
	
	sheetController.sheetType = SheetTypeSavePanel;
	if ([sheetController runModalForWindow:mainWindow] != NSOKButton) {
		return;
	}
	
	self.progressText = localized(@"GenerateRevokeCertificateForKey_Progress");
	self.errorText = localized(@"GenerateRevokeCertificateForKey_Error");
	gpgc.userInfo = @{@"action": @(SaveDataToURLAction), @"URL": sheetController.URL, @"hideExtension": @(sheetController.hideExtension)};
	[gpgc generateRevokeCertificateForKey:key reason:0 description:nil];
}

#pragma mark "Keyserver"
- (IBAction)searchKeys:(id)sender {
	sheetController.sheetType = SheetTypeSearchKeys;
	if ([sheetController runModalForWindow:mainWindow] != NSOKButton) {
		return;
	}
	
	gpgc.userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:ShowFoundKeysAction] forKey:@"action"];
	
	self.progressText = localized(@"SearchKeysOnServer_Progress");
	self.errorText = localized(@"SearchKeysOnServer_Error");
	
	
	
	NSString *pattern = sheetController.pattern;
	
	[gpgc searchKeysOnServer:pattern];
}
- (IBAction)receiveKeys:(id)sender {
	sheetController.sheetType = SheetTypeReceiveKeys;
	if ([sheetController runModalForWindow:mainWindow] != NSOKButton) {
		return;
	}
	
	NSSet *keyIDs = [sheetController.pattern keyIDs];
	
	[self receiveKeysFromServer:keyIDs];
}
- (IBAction)sendKeysToServer:(id)sender {
	NSSet *keys = [self selectedKeys];
	if (keys.count > 0) {
		self.progressText = [NSString stringWithFormat:localized(@"SendKeysToServer_Progress"), [self descriptionForKeys:keys withOptions:0]];
		self.errorText = localized(@"SendKeysToServer_Error");
		[gpgc sendKeysToServer:keys];
	}
}
- (IBAction)refreshKeysFromServer:(id)sender {
	NSSet *keys = [self selectedKeys];
	if (keys.count > 0) {
		self.progressText = [NSString stringWithFormat:localized(@"RefreshKeysFromServer_Progress"), [self descriptionForKeys:keys withOptions:0]];
		self.errorText = localized(@"RefreshKeysFromServer_Error");
		[gpgc receiveKeysFromServer:keys];
	}
}

#pragma mark "Subkeys"
- (IBAction)addSubkey:(id)sender {
	NSSet *keys = [self selectedKeys];
	if ([keys count] != 1) {
		return;
	}
	GPGKey *key = [[keys anyObject] primaryKey];
	
	sheetController.msgText = [NSString stringWithFormat:localized(@"GenerateSubkey_Msg"), [key userIDDescription], key.keyID.shortKeyID];
	
	sheetController.sheetType = SheetTypeAddSubkey;
	if ([sheetController runModalForWindow:mainWindow] != NSOKButton) {
		return;
	}
	
	self.progressText = localized(@"AddSubkey_Progress");
	self.errorText = localized(@"AddSubkey_Error");
	[gpgc addSubkeyToKey:key type:sheetController.keyType length:sheetController.length daysToExpire:sheetController.daysToExpire];
}
- (IBAction)removeSubkey:(id)sender {
	NSArray *objects = [self selectedObjectsOf:subkeysTable];
	if (objects.count != 1) {
		return;
	}
	GPGKey *subkey = [objects objectAtIndex:0];
	GPGKey *key = subkey.primaryKey;
	
	if ([self warningSheet:@"RemoveSubkey"] == NO) {
		return;
	}
	
	self.progressText = localized(@"RemoveSubkey_Progress");
	self.errorText = localized(@"RemoveSubkey_Error");
	[gpgc removeSubkey:subkey fromKey:key];
}
- (IBAction)revokeSubkey:(id)sender {
	NSArray *objects = [self selectedObjectsOf:subkeysTable];
	if (objects.count != 1) {
		return;
	}
	GPGKey *subkey = [objects objectAtIndex:0];
	GPGKey *key = subkey.primaryKey;
	
	if ([self warningSheet:@"RevokeSubkey"] == NO) {
		return;
	}
	
	self.progressText = localized(@"RevokeSubkey_Progress");
	self.errorText = localized(@"RevokeSubkey_Error");
	[gpgc revokeSubkey:subkey fromKey:key reason:0 description:nil];
}

#pragma mark "UserIDs"
- (IBAction)addUserID:(id)sender {
	NSSet *keys = [self selectedKeys];
	if ([keys count] != 1) {
		return;
	}
	GPGKey *key = [[keys anyObject] primaryKey];
	
	sheetController.msgText = [NSString stringWithFormat:localized(@"GenerateUserID_Msg"), [key userIDDescription], key.keyID.shortKeyID];
	
	sheetController.sheetType = SheetTypeAddUserID;
	if ([sheetController runModalForWindow:mainWindow] != NSOKButton) {
		return;
	}
	
	self.progressText = localized(@"AddUserID_Progress");
	self.errorText = localized(@"AddUserID_Error");
	gpgc.userInfo = @{@"action": @(SetPrimaryUserIDAction), @"userID": key.primaryUserID};
	[gpgc addUserIDToKey:key name:sheetController.name email:sheetController.email comment:sheetController.comment];
}
- (IBAction)removeUserID:(id)sender {
	NSArray *objects = [self selectedObjectsOf:userIDsTable];
	if (objects.count != 1) {
		return;
	}
	GPGUserID *userID = [objects objectAtIndex:0];
	GPGKey *key = userID.primaryKey;
	
	if ([self warningSheet:@"RemoveUserID", userID.userIDDescription, key.keyID.shortKeyID] == NO) {
		return;
	}
	
	self.progressText = localized(@"RemoveUserID_Progress");
	self.errorText = localized(@"RemoveUserID_Error");
	[gpgc removeUserID:userID.hashID fromKey:key];
}
- (IBAction)setPrimaryUserID:(id)sender {
	NSArray *objects = [self selectedObjectsOf:userIDsTable];
	if (objects.count != 1) {
		return;
	}
	GPGUserID *userID = [objects objectAtIndex:0];
	GPGKey *key = userID.primaryKey;
	
	self.progressText = localized(@"SetPrimaryUserID_Progress");
	self.errorText = localized(@"SetPrimaryUserID_Error");
	[gpgc setPrimaryUserID:userID.hashID ofKey:key];
}
- (IBAction)revokeUserID:(id)sender {
	NSArray *objects = [self selectedObjectsOf:userIDsTable];
	if (objects.count != 1) {
		return;
	}
	GPGUserID *userID = [objects objectAtIndex:0];
	GPGKey *key = userID.primaryKey;
	
	if ([self warningSheet:@"RevokeUserID", userID.userIDDescription, key.keyID.shortKeyID] == NO) {
		return;
	}
	
	self.progressText = localized(@"RevokeUserID_Progress");
	self.errorText = localized(@"RevokeUserID_Error");
	[gpgc revokeUserID:[userID hashID] fromKey:key reason:0 description:nil];
}

#pragma mark "Photos"
- (void)addPhoto:(NSString *)path toKey:(GPGKey *)key {
	
	self.progressText = localized(@"AddPhoto_Progress");
	self.errorText = localized(@"AddPhoto_Error");
	[gpgc addPhotoFromPath:path toKey:key];
}
- (IBAction)addPhoto:(id)sender {
	NSSet *keys = [self selectedKeys];
	if ([keys count] != 1) {
		return;
	}
	GPGKey *key = [[keys anyObject] primaryKey];
	if (!key.secret) {
		return;
	}
	
	sheetController.title = nil; //TODO
	sheetController.msgText = nil; //TODO
	sheetController.allowedFileTypes = [NSArray arrayWithObjects:@"jpg", @"jpeg", nil];;
	
	sheetController.sheetType = SheetTypeOpenPhotoPanel;
	if ([sheetController runModalForWindow:mainWindow] != NSOKButton) {
		return;
	}
	
	[self addPhoto:[sheetController.URL path] toKey:key];
}
- (IBAction)removePhoto:(id)sender {
	if ([photosController selectionIndex] != NSNotFound) {
		NSSet *keys = [self selectedKeys];
		GPGKey *key = [[keys anyObject] primaryKey];
		
		self.progressText = localized(@"RemovePhoto_Progress");
		self.errorText = localized(@"RemovePhoto_Error");
		[gpgc removeUserID:[[[photosController selectedObjects] objectAtIndex:0] hashID] fromKey:key];
	}
}
- (IBAction)setPrimaryPhoto:(id)sender {
	if ([photosController selectionIndex] != NSNotFound) {
		GPGKey *key = [[[self selectedKeys] anyObject] primaryKey];
		
		self.progressText = localized(@"SetPrimaryPhoto_Progress");
		self.errorText = localized(@"SetPrimaryPhoto_Error");
		[gpgc setPrimaryUserID:[[[photosController selectedObjects] objectAtIndex:0] hashID] ofKey:key];
	}
}
- (IBAction)revokePhoto:(id)sender {
	if ([photosController selectionIndex] != NSNotFound) {
		GPGKey *key = [[[self selectedKeys] anyObject] primaryKey];
		
		self.progressText = localized(@"RevokePhoto_Progress");
		self.errorText = localized(@"RevokePhoto_Error");
		[gpgc revokeUserID:[[[photosController selectedObjects] objectAtIndex:0] hashID] fromKey:key reason:0 description:nil];
	}
}

#pragma mark "Signatures"
- (IBAction)addSignature:(id)sender {
	NSSet *keys = [self selectedKeys];
	if (keys.count != 1) {
		return;
	}
	
	GPGUserID *userID = nil;
	if ([sender tag] == 1) {
		NSArray *objects = [self selectedObjectsOf:userIDsTable];
		if (objects.count != 1) {
			return;
		}
		userID = [objects objectAtIndex:0];
	}
	
	GPGKey *key = [[keys anyObject] primaryKey];
	
	NSSet *secretKeys = [[KeychainController sharedInstance] secretKeys];
	
	sheetController.secretKeys = [secretKeys allObjects];
	GPGKey *defaultKey = [[KeychainController sharedInstance] defaultKey];
	if (!defaultKey) {
		[sheetController alertSheetForWindow:mainWindow messageText:localized(@"NO_SECRET_KEY_TITLE") infoText:localized(@"NO_SECRET_KEY_MESSAGE") defaultButton:nil alternateButton:nil otherButton:nil suppressionButton:nil];
		return;
	}
	sheetController.secretKey = defaultKey;
	
	
	NSString *msgText;
	if (userID) {
		msgText = [NSString stringWithFormat:localized(@"GenerateUidSignature_Msg"), [NSString stringWithFormat:@"%@ (%@)", userID.userIDDescription, key.keyID.shortKeyID]];
	} else {
		msgText = [NSString stringWithFormat:localized(@"GenerateSignature_Msg"), key.userIDAndKeyID];
	}
	
	sheetController.msgText = msgText;
	
	sheetController.sheetType = SheetTypeAddSignature;
	if ([sheetController runModalForWindow:mainWindow] != NSOKButton) {
		return;
	}
	
	self.progressText = localized(@"AddSignature_Progress");
	self.errorText = localized(@"AddSignature_Error");
	[gpgc signUserID:[userID hashID] ofKey:key signKey:sheetController.secretKey type:sheetController.sigType local:sheetController.localSig daysToExpire:sheetController.daysToExpire];
}
- (IBAction)removeSignature:(id)sender {
	NSArray *objects = [self selectedObjectsOf:signaturesTable];
	if (objects.count != 1) {
		return;
	}
	GPGUserIDSignature *signature = [objects objectAtIndex:0];
	GPGUserID *userID = [[userIDsController selectedObjects] objectAtIndex:0];
	GPGKey *key = userID.primaryKey;
	BOOL lastSelfSignature = NO;
	
	if ([signature.primaryKey isEqualTo:key] && !signature.revocation) {
		NSArray *signatures = userID.signatures;
		NSInteger count = 0;
		for (GPGUserIDSignature *sig in signatures) {
			if ([sig.primaryKey isEqualTo:key]) {
				count++;
				if (count > 1) {
					break;
				}
			}
		}
		lastSelfSignature = (count == 1);
	}
	
	NSString *warningTemplate = lastSelfSignature ? @"RemoveLastSelfSignature" : @"RemoveSignature";
	if ([self warningSheet:warningTemplate, signature.userIDDescription, signature.keyID.shortKeyID, userID.userIDDescription, key.keyID.shortKeyID] == NO) {
		return;
	}

	
	self.progressText = localized(@"RemoveSignature_Progress");
	self.errorText = localized(@"RemoveSignature_Error");
	[gpgc removeSignature:signature fromUserID:userID ofKey:key];
}
- (IBAction)revokeSignature:(id)sender {
	NSArray *objects = [self selectedObjectsOf:signaturesTable];
	if (objects.count != 1) {
		return;
	}
	GPGUserIDSignature *signature = [objects objectAtIndex:0];
	GPGUserID *userID = [[userIDsController selectedObjects] objectAtIndex:0];
	GPGKey *key = userID.primaryKey;
	BOOL lastSelfSignature = NO;
	
	if ([signature.primaryKey isEqualTo:key] && !signature.revocation) {
		NSArray *signatures = userID.signatures;
		NSInteger count = 0;
		for (GPGUserIDSignature *sig in signatures) {
			if ([sig.primaryKey isEqualTo:key]) {
				count++;
				if (count > 1) {
					break;
				}
			}
		}
		lastSelfSignature = (count == 1);
	}
	
	NSString *warningTemplate = lastSelfSignature ? @"RevokeLastSelfSignature" : @"RevokeSignature";
	if ([self warningSheet:warningTemplate, signature.userIDDescription, signature.keyID.shortKeyID, userID.userIDDescription, key.keyID.shortKeyID] == NO) {
		return;
	}
	
	self.progressText = localized(@"RevokeSignature_Progress");
	self.errorText = localized(@"RevokeSignature_Error");
	[gpgc revokeSignature:signature fromUserID:userID ofKey:key reason:0 description:nil];
}




#pragma mark "Miscellaneous :)"
- (void)cancelOperation:(id)sender {
	[gpgc cancel];
}

- (void)receiveKeysFromServer:(NSObject <EnumerationList> *)keys {
	gpgc.userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:ShowResultAction] forKey:@"action"];
	
	self.progressText = localized(@"ReceiveKeysFromServer_Progress");
	self.errorText = localized(@"ReceiveKeysFromServer_Error");
	[gpgc receiveKeysFromServer:keys];
}

- (NSString *)importResultWithStatusDict:(NSDictionary *)statusDict {
	int publicKeysCount, publicKeysOk, publicKeysNoChange, secretKeysCount, secretKeysOk, userIDCount, subkeyCount, signatureCount, revocationCount;
	int flags;
	NSString *fingerprint, *keyID, *userID;
	NSArray *importRes = nil;
	NSMutableArray *lines = [NSMutableArray array];
	NSMutableDictionary *changedKeys = [NSMutableDictionary dictionary];
	NSNumber *no = [NSNumber numberWithBool:NO], *yes = [NSNumber numberWithBool:YES];
	NSSet *allKeys = [(KeychainController *)[KeychainController sharedInstance] allKeys];
	
	NSArray *importResList = [statusDict objectForKey:@"IMPORT_RES"];
	NSArray *importOkList = [statusDict objectForKey:@"IMPORT_OK"];
	
	for (NSArray *importOk in importOkList) {
		flags = [[importOk objectAtIndex:0] intValue];
		fingerprint = [importOk objectAtIndex:1];
		
		userID = [[allKeys member:fingerprint] userIDDescription];
		if (!userID) userID = @"";
		keyID = [fingerprint shortKeyID];
		
		
		if (flags > 0) {
			if (flags & 1) {
				if (flags & 16) {
					[lines addObject:[NSString stringWithFormat:localized(@"ImportResult_Secret"), keyID, userID]];
				} else {
					[lines addObject:[NSString stringWithFormat:localized(@"ImportResult_Public"), keyID, userID]];
				}
			}
			if (flags & 2) {
				[lines addObject:[NSString stringWithFormat:localized(@"ImportResult_UserID"), keyID, userID]];
			}
			if (flags & 4) {
				[lines addObject:[NSString stringWithFormat:localized(@"ImportResult_Signature"), keyID, userID]];
			}
			if (flags & 8) {
				[lines addObject:[NSString stringWithFormat:localized(@"ImportResult_Subkey"), keyID, userID]];
			}
			[changedKeys setObject:yes forKey:fingerprint];
		} else {
			if ([changedKeys objectForKey:fingerprint] == nil) {
				[changedKeys setObject:no forKey:fingerprint];
			}
		}
	}
	
	
	
	for (fingerprint in [changedKeys allKeysForObject:no]) {
		userID = [[allKeys member:fingerprint] userIDDescription];
		if (!userID) userID = @"";
		keyID = [fingerprint shortKeyID];
		
		[lines addObject:[NSString stringWithFormat:localized(@"ImportResult_KeyNoChanges"), keyID, userID]];
	}
	
	
	
	if ([importResList count] > 0) {
		importRes = [importResList objectAtIndex:0];
		
		publicKeysCount = [[importRes objectAtIndex:0] intValue];
		publicKeysOk = [[importRes objectAtIndex:2] intValue];
		publicKeysNoChange = [[importRes objectAtIndex:4] intValue];
		userIDCount = [[importRes objectAtIndex:5] intValue];
		subkeyCount = [[importRes objectAtIndex:6] intValue];
		signatureCount = [[importRes objectAtIndex:7] intValue];
		revocationCount = [[importRes objectAtIndex:8] intValue];
		secretKeysCount = [[importRes objectAtIndex:9] intValue];
		secretKeysOk = [[importRes objectAtIndex:10] intValue];
		
		
		//TODO: More infos.
		
		if (revocationCount > 0) {
			if (revocationCount == 1) {
				[lines addObject:[NSString stringWithFormat:localized(@"ImportResult_OneRevocationCertificate"), @""]];
			} else {
				[lines addObject:[NSString stringWithFormat:localized(@"ImportResult_CountRevocationCertificate"), revocationCount]];
			}
		}
		
		if ([lines count] > 0) {
			[lines addObject:@""];
		}
		
		[lines addObject:[NSString stringWithFormat:localized(@"ImportResult_CountProcessed"), publicKeysCount]];
		if (publicKeysOk > 0) {
			[lines addObject:[NSString stringWithFormat:localized(@"ImportResult_CountImported"), publicKeysOk]];
		}
		if (publicKeysNoChange > 0) {
			[lines addObject:[NSString stringWithFormat:localized(@"ImportResult_CountUnchanged"), publicKeysNoChange]];
		}
	}
	
	
	return [lines componentsJoinedByString:@"\n"];
}

- (NSUndoManager *)undoManager {
	if (!undoManager) {
		undoManager = [NSUndoManager new];
		[undoManager setLevelsOfUndo:50];
	}
	return [[undoManager retain] autorelease];
}

- (NSSet *)selectedKeys {
	NSInteger clickedRow = [keyTable clickedRow];
	if (clickedRow != -1 && ![keyTable isRowSelected:clickedRow]) {
		return [NSSet setWithObject:[[keyTable itemAtRow:clickedRow] representedObject]];
	} else {
		NSMutableSet *keySet = [NSMutableSet set];
		for (GPGKey *key in [keysController selectedObjects]) {
			[keySet addObject:[key primaryKey]];
		}
		return keySet;
	}
}
- (NSArray *)selectedObjectsOf:(NSTableView *)table {
	NSArrayController *arrayController;
	if (table == userIDsTable) {
		arrayController = userIDsController;
	} else if (table == signaturesTable) {
		arrayController = signaturesController;
	} else if (table == subkeysTable) {
		arrayController = subkeysController;
	} else {
		return nil;
	}

	NSInteger clickedRow = [table clickedRow];
	if (clickedRow != -1 && ![table isRowSelected:clickedRow]) {
		return @[[arrayController.arrangedObjects objectAtIndex:clickedRow]];
	} else {
		return [arrayController selectedObjects];
	}
}


- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)item {
    SEL selector = item.action;
	NSInteger tag = item.tag;
	
    if (selector == @selector(copy:)) {
		return self.selectedKeys.count > 0;
    }
	else if (selector == @selector(paste:)) {
		NSPasteboard *pboard = [NSPasteboard generalPasteboard];
		NSArray *types = [pboard types];
		if ([types containsObject:NSFilenamesPboardType]) {
			return YES;
		} else if ([types containsObject:NSStringPboardType]) {
			NSString *string = [pboard stringForType:NSStringPboardType];
			if (containsPGPKeyBlock(string)) {
				return YES;
			} else {
				return NO;
			}
		}
    }
	else if (selector == @selector(genRevokeCertificate:)) {
		NSSet *keys = [self selectedKeys];
		return (keys.count == 1 && ((GPGKey*)[keys anyObject]).secret);
    }
	else if (selector == @selector(editAlgorithmPreferences:)) {
		return self.selectedKeys.count == 1;
	}
	else if (selector == @selector(sendKeysToServer:)) {
		return self.selectedKeys.count > 0;
	}
	else if (selector == @selector(refreshKeysFromServer:)) {
		return self.selectedKeys.count > 0;
	}
	else if (selector == @selector(addSignature:)) {
		if (tag == 1) {
			return [self selectedObjectsOf:userIDsTable].count == 1;
		}
	}
	else if (selector == @selector(removeUserID:)) {
		return [self selectedObjectsOf:userIDsTable].count == 1;
	}
	else if (selector == @selector(revokeUserID:)) {
		NSArray *objects = [self selectedObjectsOf:userIDsTable];
		return objects.count == 1 && [[objects objectAtIndex:0] primaryKey].secret;
	}
	else if (selector == @selector(setPrimaryUserID:)) {
		NSArray *objects = [self selectedObjectsOf:userIDsTable];
		return objects.count == 1 && [[objects objectAtIndex:0] primaryKey].secret;
	}
	else if (selector == @selector(removeSignature:)) {
		return [self selectedObjectsOf:signaturesTable].count == 1;
	}
	else if (selector == @selector(revokeSignature:)) {
		NSArray *objects = [self selectedObjectsOf:signaturesTable];
		if (objects.count != 1) {
			return NO;
		}
		GPGUserIDSignature *sig = [objects objectAtIndex:0];
		return !sig.revocation && sig.primaryKey.secret;
	}
	else if (selector == @selector(removeSubkey:)) {
		return [self selectedObjectsOf:subkeysTable].count == 1;
	}
	else if (selector == @selector(revokeSubkey:)) {
		NSArray *objects = [self selectedObjectsOf:subkeysTable];
		return objects.count == 1 && [[objects objectAtIndex:0] primaryKey].secret;
	}
	else if (selector == @selector(changeExpirationDate:)) {
		if (tag == 1) {
			NSArray *objects = [self selectedObjectsOf:subkeysTable];
			return objects.count == 1 && [[objects objectAtIndex:0] primaryKey].secret;
		}
	}

	return YES;
}

- (BOOL)respondsToSelector:(SEL)selector {
	if (selector == @selector(copy:)) {
		NSResponder *responder = mainWindow.firstResponder;
		
		if (responder == appDelegate.userIDTable) {
			if (userIDsController.selectedObjects.count == 1) {
				return YES;
			}
		} else if (responder == appDelegate.signatureTable) {
			if (signaturesController.selectedObjects.count == 1) {
				return YES;
			}
		} else if (responder == appDelegate.subkeyTable) {
			if (subkeysController.selectedObjects.count == 1) {
				return YES;
			}
		} else if ([self selectedKeys].count > 0) {
			return YES;
		}
		return NO;
	}
	
	return [super respondsToSelector:selector];
}

- (NSString *)descriptionForKeys:(NSObject <EnumerationList> *)keys withOptions:(NSUInteger)options {
	NSMutableArray *descriptions = [NSMutableArray array];
	Class gpgKeyClass = [GPGKey class];
	
	for (GPGKey *key in keys) {
		NSString *description;
		if ([key isKindOfClass:gpgKeyClass]) {
			description = [NSString stringWithFormat:@"%@ (%@)", key.userIDDescription, key.keyID.shortKeyID];
		} else {
			description = key.keyID;
		}
		
		[descriptions addObject:description];
	}
	
	return [descriptions componentsJoinedByString:@", "];
}

- (BOOL)warningSheet:(NSString *)string, ... {
	NSInteger returnCode;
	NSString *message = localized([string stringByAppendingString:@"_Msg"]);
	
	va_list args;
	va_start(args, string);
	message = [[[NSString alloc] initWithFormat:message arguments:args] autorelease];
	va_end(args);
	
	returnCode = [sheetController alertSheetForWindow:mainWindow
										  messageText:localized([string stringByAppendingString:@"_Title"])
											 infoText:message
										defaultButton:localized([string stringByAppendingString:@"_Yes"])
									  alternateButton:localized([string stringByAppendingString:@"_No"])
										  otherButton:nil
									suppressionButton:nil];
	
	return (returnCode == NSAlertFirstButtonReturn);
}


#pragma mark "Delegate"
- (void)gpgControllerOperationDidStart:(GPGController *)gc {
	sheetController.progressText = self.progressText;
	[sheetController performSelectorOnMainThread:@selector(showProgressSheet) withObject:nil waitUntilDone:YES];
}
- (void)gpgController:(GPGController *)gc operationThrownException:(NSException *)e {
	NSString *title, *message;
	GPGException *ex = nil;
	GPGTask *gpgTask = nil;
	NSDictionary *userInfo = gc.userInfo;
	
	
	NSLog(@"Exception: %@", e.description);

	if ([e isKindOfClass:[GPGException class]]) {
		ex = (GPGException *)e;
		gpgTask = ex.gpgTask;
		if (ex.errorCode == GPGErrorCancelled) {
			return;
		}
		NSLog(@"Error text: %@\nStatus text: %@", gpgTask.errText, gpgTask.statusText);
	}
	
	
	switch ([[userInfo objectForKey:@"operation"] integerValue]) {
		case ImportOperation:
			if (![[userInfo objectForKey:@"containsImportable"] boolValue]) {
				if ([[userInfo objectForKey:@"containsNonImportable"] boolValue]) {
					title = localized(@"ImportKeyErrorPGP_Title");
					message = localized(@"ImportKeyErrorPGP_Msg");
				} else {
					title = localized(@"ImportKeyErrorNoPGP_Title");
					message = localized(@"ImportKeyErrorNoPGP_Msg");
				}
			} else {
				title = localized(@"ImportKeyError_Title");
				message = localized(@"ImportKeyError_Msg");
			}
			break;
		default:
			title = self.errorText;
			if (gpgTask) {
				message = [NSString stringWithFormat:@"%@\n\nError text:\n%@", e.description, gpgTask.errText];
			} else {
				message = [NSString stringWithFormat:@"%@", e.description];
			}
			break;
	}
	
	
	[sheetController errorSheetWithmessageText:title infoText:message];
}
- (void)gpgController:(GPGController *)gc operationDidFinishWithReturnValue:(id)value {
	NSDictionary *oldUserInfo = [gc.userInfo retain];
	gc.userInfo = nil;
	self.progressText = nil;
	self.errorText = nil;
	
	NSInteger action = [[oldUserInfo objectForKey:@"action"] integerValue];
	
	switch (action) {
		case ShowResultAction: {
			if (gc.error) break;
			
			NSDictionary *statusDict = gc.statusDict;
			if (statusDict) {
				[self refreshDisplayedKeys:self];
				
				sheetController.msgText = [self importResultWithStatusDict:statusDict];
				sheetController.sheetType = SheetTypeShowResult;
				[sheetController runModalForWindow:mainWindow];
			}
			break;
		}
		case ShowFoundKeysAction: {
			if (gc.error) break;
			NSArray *keys = gc.lastReturnValue;
			if ([keys count] == 0) {
				sheetController.msgText = localized(@"No keys Found");
				sheetController.sheetType = SheetTypeShowResult;
				[sheetController runModalForWindow:mainWindow];
			} else {
				sheetController.keys = keys;
				
				sheetController.sheetType = SheetTypeShowFoundKeys;
				if ([sheetController runModalForWindow:mainWindow] != NSOKButton) break;
				
				[self receiveKeysFromServer:sheetController.keys];
			}
			break;
		}
		case SaveDataToURLAction: {
			if (gc.error) break;
			
			NSURL *URL = [oldUserInfo objectForKey:@"URL"];
			NSNumber *hideExtension = @([[oldUserInfo objectForKey:@"hideExtension"] boolValue]);
			[[NSFileManager defaultManager] createFileAtPath:URL.path contents:value attributes:@{NSFileExtensionHidden: hideExtension}];
			
			break;
		}
		case UploadKeyAction:
			if (gc.error || !value) break;
			
			self.progressText = localized(@"SendKeysToServer_Progress");
			self.errorText = localized(@"SendKeysToServer_Error");
			
			[gpgc sendKeysToServer:[NSSet setWithObject:value]];
			
			break;
		case SetPrimaryUserIDAction:
			if (gc.error) break;
			
			GPGUserID *userID = [oldUserInfo objectForKey:@"userID"];
			self.progressText = localized(@"SetPrimaryUserID_Progress");
			self.errorText = localized(@"SetPrimaryUserID_Error");
			[gpgc setPrimaryUserID:userID.hashID ofKey:userID.primaryKey];
			
			break;
		case SetTrustAction: {
			NSMutableSet *keys = [oldUserInfo objectForKey:@"keys"];
			NSInteger *trust = [[oldUserInfo objectForKey:@"trust"] integerValue];
			
			[self setTrust:trust forKeys:keys];
			break;
		}
		case SetDisabledAction: {
			NSMutableSet *keys = [oldUserInfo objectForKey:@"keys"];
			BOOL *disabled = [[oldUserInfo objectForKey:@"disabled"] boolValue];
			
			[self setDisabled:disabled forKeys:keys];
			break;
		}
		default:
			break;
	}
	
	[sheetController performSelectorOnMainThread:@selector(endProgressSheet) withObject:nil waitUntilDone:NO];
	
	[oldUserInfo release];
}



#pragma mark "Singleton: alloc, init etc."
+ (id)sharedInstance {
	static id sharedInstance = nil;
    if (!sharedInstance) {
        sharedInstance = [[super allocWithZone:nil] init];
    }
    return sharedInstance;
}
- (id)init {
	static BOOL initialized = NO;
	if (!initialized) {
		initialized = YES;
		self = [super init];
		
		gpgc = [[GPGController gpgController] retain];
		gpgc.delegate = self;
		gpgc.undoManager = self.undoManager;
		gpgc.printVersion = YES;
		gpgc.async = YES;
		gpgc.keyserverTimeout = 20;
		sheetController = [[SheetController sharedInstance] retain];
	}
	return self;
}
+ (id)allocWithZone:(NSZone *)zone {
    return [[self sharedInstance] retain];
}
- (id)copyWithZone:(NSZone *)zone {
    return self;
}
- (id)retain {
    return self;
}
- (NSUInteger)retainCount {
    return NSUIntegerMax;
}
- (oneway void)release {
}
- (id)autorelease {
    return self;
}


@end

