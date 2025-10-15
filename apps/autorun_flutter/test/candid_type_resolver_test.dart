import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/utils/candid_type_resolver.dart';

void main() {
  test('resolves type aliases and nested wrappers', () {
    const candid = r'''
      // Aliases
      type NeuronId = record { id: nat64 };
      type NeuronIdOrSubaccount = variant { NeuronId; Subaccount };
      type ListNeurons = record {
        limit: nat32;
        start_page_at: opt NeuronId;
      };
      service : {
        list_neurons: (ListNeurons) -> (vec NeuronId);
      }
    ''';

    final resolver = CandidTypeResolver(candid);
    final out = resolver.resolveArgTypes(<String>['ListNeurons']);
    expect(out.length, 1);
    expect(out.first.contains('record'), true);
    expect(out.first.contains('limit : nat32'), true);
    expect(out.first.contains('start_page_at : opt record'), true);
  });
}
