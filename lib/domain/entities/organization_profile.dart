class OrganizationProfile {
  const OrganizationProfile({
    required this.companyId,
    required this.name,
    required this.officialEmail,
    required this.phone,
    required this.address,
    required this.inventoryAlertsEnabled,
    required this.autoApproveRepeatOrders,
    required this.requireInvoiceVerification,
  });

  final String companyId;
  final String name;
  final String officialEmail;
  final String phone;
  final String address;
  final bool inventoryAlertsEnabled;
  final bool autoApproveRepeatOrders;
  final bool requireInvoiceVerification;

  OrganizationProfile copyWith({
    String? companyId,
    String? name,
    String? officialEmail,
    String? phone,
    String? address,
    bool? inventoryAlertsEnabled,
    bool? autoApproveRepeatOrders,
    bool? requireInvoiceVerification,
  }) {
    return OrganizationProfile(
      companyId: companyId ?? this.companyId,
      name: name ?? this.name,
      officialEmail: officialEmail ?? this.officialEmail,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      inventoryAlertsEnabled:
          inventoryAlertsEnabled ?? this.inventoryAlertsEnabled,
      autoApproveRepeatOrders:
          autoApproveRepeatOrders ?? this.autoApproveRepeatOrders,
      requireInvoiceVerification:
          requireInvoiceVerification ?? this.requireInvoiceVerification,
    );
  }
}
