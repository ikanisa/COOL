# Sourced by both JVM harnesses after HERE is set to the BuriMunsi project root.
BURI_CONTROLLER_SOURCES=()
for controller_source in \
    gateway/GatewayPort export/ListingExportData SessionNetworkObserver \
    ui/BuriController ui/BuriViewModel ui/UiState ui/UiFeedbackModels ui/MemberImportInputs \
    ui/NativeCollectionPosting ui/NativeListingDownloads ui/NativeListingQueries ui/NativeMemberDirectory ui/NativeMemberRegistration \
    ui/NativeNavigationCheckpoints ui/NativeOperationIo ui/NativePagedRestoration \
    ui/NativeReceiverQueuePreview ui/NativeReceiverStatus ui/NativeSessionBootstrap ui/NativeSmsDisclosure ui/NativeSmsInboxScan
do
    BURI_CONTROLLER_SOURCES+=("$HERE/app/src/main/kotlin/rw/ikanisa/burimunsi/$controller_source.kt")
done
